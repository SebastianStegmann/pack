package main

// Rectangle packing by simulated annealing over sequence pairs,
// following Murata et al. 1996 (Sections III and IV-A):
//   - every module is placed, there is no fixed container
//   - objective: minimise the area of the bounding rectangle (the "chip")
//   - moves: swap two modules in Γ+, swap two modules in both Γ+ and Γ-,
//            rotate a module (swap w and h)
//   - start from Γ+ = Γ- (all modules in one horizontal row)
//   - exponential cooling

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:os"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"
import "core:time"

INSTANCE        :: "data/ep2/ep2-30-W-R-25.2kp"
STEPS_PER_FRAME :: 3000 // annealing moves pr rendered frame
LIVE            :: true

Container :: struct {
    w, h: int,
}

Module :: struct {
    id, w, h: int,
}

// A sequence pair plus an orientation per module.
// pos and neg are permutations of 0..n-1 (indices into the modules slice).
State :: struct {
    pos, neg: []int,
    rotated:  []bool,
} 

// Top-left corner of each module, in raylib's y-down coordinates.
Layout :: struct {
    x, y: []int,
    w, h: int, // chip size
}

Move_Kind :: enum {
    Swap_Pos,  // swap modules a and b in Γ+ only
    Swap_Both, // swap modules a and b in Γ+ and Γ-
    Rotate,    // swap width and height of module a
}

// a and b are module ids. Every move is its own inverse,
// so applying the same move again undoes it.
Move :: struct {
    kind: Move_Kind,
    a, b: int,
}

Annealer :: struct {
    modules:        []Module,
    cur, best:      State,
    lay, best_lay:  Layout,
    rank_n:         []int, // scratch: position of each module in Γ-
    cur_cost:       f64,
    best_cost:      f64,
    temp, t0:       f64,
    t_min, alpha:   f64,
    moves_per_temp: int,
    moves_at_temp:  int,
    total_moves:    int,
    accepted:       int,
    done:           bool,
}

// ---------------------------------------------------------------------------
// Sequence pair -> packing  (Murata Sec. III-B)
// ---------------------------------------------------------------------------

dims :: proc(m: Module, rotated: bool) -> (w, h: int) {
    if rotated do return m.h, m.w
    return m.w, m.h
}

// Longest path through the horizontal and vertical constraint graphs.
// Both graphs only have edges a -> b where a comes before b in Γ+,
// so walking Γ+ in order is a topological order for both and we never
// need to build the graphs explicitly. O(n^2), no allocations.
evaluate :: proc(modules: []Module, s: State, lay: ^Layout, rank_n: []int) {
    // rank[id] = where is module [id]
    for id, i in s.neg do rank_n[id] = i

    lay.w, lay.h = 0, 0
    // b: what module, bi: what position in pos seq
    for b, bi in s.pos {
        // get module size, possible rotated
        bw, bh := dims(modules[b], s.rotated[b])
        // reset coordinates
        x, y := 0, 0
        // look at every module places before current
        // as these can only affect the modules position
        // coordinates of first module is 0, so this doesnt run first time
        for a in s.pos[:bi] {
            aw, ah := dims(modules[a], s.rotated[a])
            // we already know a comes before p in pos
            // so check position in neg
            if rank_n[a] < rank_n[b] {
                x = max(x, lay.x[a] + aw) // a before b in both: a left of b
            } else {
                y = max(y, lay.y[a] + ah) // a before in pos, after in neg: a above b
            }
        }
        // set the x and y coordinates for the b module
        lay.x[b], lay.y[b] = x, y
        // increase layout size if the added module made it bigger
        lay.w = max(lay.w, x + bw)
        lay.h = max(lay.h, y + bh)
    }
}

cost :: proc(lay: Layout) -> f64 {
    return f64(lay.w) * f64(lay.h)
}

// ---------------------------------------------------------------------------
// Moves
// ---------------------------------------------------------------------------

swap_ids :: proc(seq: []int, a, b: int) {
    ia, ib := -1, -1
    for v, k in seq {
        if v == a do ia = k
        if v == b do ib = k
    }
    seq[ia], seq[ib] = seq[ib], seq[ia]
}

apply_move :: proc(s: ^State, m: Move) {
    switch m.kind {
    case .Swap_Pos:
        swap_ids(s.pos, m.a, m.b)
    case .Swap_Both:
        swap_ids(s.pos, m.a, m.b)
        swap_ids(s.neg, m.a, m.b)
    case .Rotate:
        s.rotated[m.a] = !s.rotated[m.a]
    }
}

// progress goes from 0 (hot) to 1 (cold). As in the paper, Γ+-only swaps
// are favoured early and rotations late.
random_move :: proc(n: int, progress: f64) -> Move {
    // picks a first, 0 1 _2_ 3 4
    // we then pick b from n - 1 list, 0 1 _2_ 3  
    // if b is the same or bigger than a we +1, so it's never the same as a
    a := rand.int_max(n)
    b := rand.int_max(n - 1)
    if b >= a do b += 1

    // start at 50% chance swap, 10% rotate, rest swap_both
    p_pos := 0.5 - 0.3 * progress
    p_rot := 0.1 + 0.3 * progress
    r := rand.float64()
    switch {
    case r < p_pos:
        return {.Swap_Pos, a, b}
    case r < p_pos + p_rot:
        return {.Rotate, a, b}
    }
    return {.Swap_Both, a, b}
}

// ---------------------------------------------------------------------------
// Simulated annealing
// ---------------------------------------------------------------------------

make_state :: proc(n: int) -> State {
    return {make([]int, n), make([]int, n), make([]bool, n)}
}

copy_state :: proc(dst: ^State, src: State) {
    copy(dst.pos, src.pos)
    copy(dst.neg, src.neg)
    copy(dst.rotated, src.rotated)
}

make_layout :: proc(n: int) -> Layout {
    return {x = make([]int, n), y = make([]int, n)}
}

copy_layout :: proc(dst: ^Layout, src: Layout) {
    copy(dst.x, src.x)
    copy(dst.y, src.y)
    dst.w, dst.h = src.w, src.h
}

init_annealer :: proc(an: ^Annealer, modules: []Module) {
    n := len(modules)
    an^ = {}
    an.modules = modules
    an.cur = make_state(n)
    an.best = make_state(n)
    an.lay = make_layout(n)
    an.best_lay = make_layout(n)
    an.rank_n = make([]int, n)

    // Γ+ = Γ-: every module left of the next, one horizontal row.
    for i in 0 ..< n {
        an.cur.pos[i] = i
        an.cur.neg[i] = i
    }

    // i added this because the sequence starting in a row lead to 85% solved for 200 modules
    // rand.shuffle(an.cur.neg)


    evaluate(modules, an.cur, &an.lay, an.rank_n)
    an.cur_cost = cost(an.lay)
    an.best_cost = an.cur_cost
    copy_state(&an.best, an.cur)
    copy_layout(&an.best_lay, an.lay)

    // see how much an average bad move increases the cost
    // runs the changes, counts, then reverts
    sum, count := 0.0, 0
    for _ in 0 ..< 200 {
        mv := random_move(n, 0)
        apply_move(&an.cur, mv)
        evaluate(modules, an.cur, &an.lay, an.rank_n)
        d := cost(an.lay) - an.cur_cost
        if d > 0 {
            sum += d
            count += 1
        }
        apply_move(&an.cur, mv)
    }

    // we took the average bad move
    // make it so average bad move has 90% chance of being accepted
    avg := count > 0 ? sum / f64(count) : an.cur_cost * 0.1


    // initial temp P = e^-delta E / T
    an.t0 = -avg / math.ln(f64(0.9))

    an.temp = an.t0

    // cool down to 1000x smaller than start temp
    an.t_min = an.t0 * 1e-4
    // cooling rate
    an.alpha = 0.95
    an.moves_per_temp = 100 * n
}

destroy_annealer :: proc(an: ^Annealer) {
    delete(an.cur.pos); delete(an.cur.neg); delete(an.cur.rotated)
    delete(an.best.pos); delete(an.best.neg); delete(an.best.rotated)
    delete(an.lay.x); delete(an.lay.y)
    delete(an.best_lay.x); delete(an.best_lay.y)
    delete(an.rank_n)
}

anneal_step :: proc(an: ^Annealer) {
    if an.done do return

    // Divides current temperature change with total temperature change
    progress := math.ln(an.t0 / an.temp) / math.ln(an.t0 / an.t_min)
    mv := random_move(len(an.modules), progress)

    apply_move(&an.cur, mv)
    evaluate(an.modules, an.cur, &an.lay, an.rank_n)
    c := cost(an.lay)
    delta := c - an.cur_cost

    // if delta <= 0 {
    if delta <= 0 || rand.float64() < math.exp(-delta / an.temp) {
        an.cur_cost = c
        an.accepted += 1
        if c < an.best_cost {
            an.best_cost = c
            copy_state(&an.best, an.cur)
            copy_layout(&an.best_lay, an.lay)
        }
    } else {
        apply_move(&an.cur, mv) // undo
    }

    an.total_moves += 1
    an.moves_at_temp += 1
    if an.moves_at_temp >= an.moves_per_temp {
        an.moves_at_temp = 0
        an.temp *= an.alpha
        if an.temp < an.t_min do an.done = true
    }
}

anneal :: proc(an: ^Annealer) {
    for !an.done do anneal_step(an)
}

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------

field :: proc(parts: []string, i: int) -> int {
    v, _ := strconv.parse_int(parts[i])
    return v
}

// Format:
// rect, id, w, h
load_instance :: proc(path: string) -> (modules: [dynamic]Module, ok: bool) {
    data, err := os.read_entire_file(path, context.allocator)
    if err != nil {
        fmt.eprintln("could not read", path, err)
        return
    }
    defer delete(data)

    it := string(data)

    // skip container
    _,_ = strings.split_lines_iterator(&it)

    for line in strings.split_lines_iterator(&it) {

        // assumes every file is formatted correctly
        parts := strings.split(line, ", ")
        defer delete(parts)

        m := Module{field(parts, 1), field(parts, 2), field(parts, 3)}
        append(&modules, m)
    }
    return modules, len(modules) >= 2
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

main :: proc() {
    modules, ok := load_instance(INSTANCE)
    if !ok do return
    defer delete(modules)

    // used for util %
    total_area := 0
    for m in modules do total_area += m.w * m.h

    an: Annealer
    init_annealer(&an, modules[:])
    defer destroy_annealer(&an)


    when !LIVE {
        start := time.tick_now()
        anneal(&an)
        elapsed := time.tick_since(start)
        lay := an.best_lay
        fmt.printfln("chip %d x %d = %d, utilisation %.1f%%, %d moves in %v",
            lay.w, lay.h, lay.w * lay.h,
            100 * f64(total_area) / an.best_cost,
            an.total_moves, elapsed)
    }

        show(modules[:], &an, total_area)

        fmt.println(an.best)
        // fmt.println(elapsed)

    
}

show :: proc(modules: []Module, an: ^Annealer, total_area: int) {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT})
    rl.InitWindow(1200, 900, "Sequence-pair annealing")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    n := len(modules)

    for !rl.WindowShouldClose() {
        if rl.IsKeyPressed(.R) {
            destroy_annealer(an)
            init_annealer(an, modules[:])
            when !LIVE do anneal(an)
        }

        when LIVE {
            for _ in 0 ..< STEPS_PER_FRAME {
                if an.done do break
                anneal_step(an)
            }
        }

        lay := an.best_lay
        margin  :: 40
        text_h  :: 90
        avail_w := f32(rl.GetScreenWidth()) - 2 * margin
        avail_h := f32(rl.GetScreenHeight()) - 2 * margin - text_h
        scale   := min(avail_w / f32(lay.w), avail_h / f32(lay.h))
        ox      := f32(margin)
        oy      := f32(margin + text_h)

        rl.BeginDrawing()
        rl.ClearBackground(rl.RAYWHITE)

        for m, i in modules {
            w, h := dims(m, an.best.rotated[i])
            r := rl.Rectangle{
                ox + f32(lay.x[i]) * scale,
                oy + f32(lay.y[i]) * scale,
                f32(w) * scale,
                f32(h) * scale,
            }
            rl.DrawRectangleRec(r, rl.ColorFromHSV(f32(i) * 360 / f32(n), 0.45, 0.95))
            rl.DrawRectangleLinesEx(r, 1, rl.DARKGRAY)
            if r.width > 14 && r.height > 12 {
                rl.DrawText(fmt.ctprintf("%d", i), i32(r.x) + 3, i32(r.y) + 2, 10, rl.BLACK)
            }
        }

        // Chip outline
        rl.DrawRectangleLinesEx(
            {ox, oy, f32(lay.w) * scale, f32(lay.h) * scale},
            2, rl.RED,
        )

        util := 100 * f64(total_area) / an.best_cost
        status := an.done ? "done" : "annealing"
        rl.DrawText(
            fmt.ctprintf("%s  |  chip %d x %d = %d  |  module area %d  |  utilisation %.1f%%",
                status, lay.w, lay.h, lay.w * lay.h, total_area, util),
            margin, 15, 20, rl.BLACK,
        )
        rl.DrawText(
            fmt.ctprintf("T = %.2f  |  moves %d  |  accepted %d  |  R to restart",
                an.temp, an.total_moves, an.accepted),
            margin, 42, 18, rl.DARKGRAY,
        )
        rl.DrawText("red: chip (bounding box)",
            margin, 66, 16, rl.GRAY)

        rl.EndDrawing()
        free_all(context.temp_allocator)
    }
}
