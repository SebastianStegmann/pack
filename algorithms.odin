package main

import "core:slice"
import "core:math/rand"
import "core:fmt"
import "core:math"
import "core:time"

State :: struct {
    pos, neg: []int,
    rotated:  []bool,
} 

Layout :: struct {
    x, y: []int,
    w, h: int, // chip size
}

Move_Kind :: enum {
    Swap_Pos,  // swap modules a and b in pos only
    Swap_Both, // swap modules a and b in pos and neg
    Rotate,    // swap width and height of module
}

Move :: struct {
    kind: Move_Kind,
    a, b: int,
}

Search :: struct {
    modules:        []Module,
    cur, best:      State,
    lay, best_lay:  Layout,
    eval:           Eval_Scratch,
    cur_cost:       f64,
    best_cost:      f64,
    total_moves:    int,
    accepted:       int,
    done:           bool,
}

Annealer :: struct {
    using search:   Search,
    temp, t0:       f64,
    t_min, alpha:   f64,
    moves_per_temp: int,
    moves_at_temp:  int,
}

Hillclimber :: struct {
    using search:   Search,
    since_improve:  int,
    restart_after:  int,
    restarts:       int,
    progress:       f64,
}


destroy_hillcilmber:: proc(hc: ^Hillclimber) {
    delete(hc.cur.pos); delete(hc.cur.neg); delete(hc.cur.rotated)
    delete(hc.best.pos); delete(hc.best.neg); delete(hc.best.rotated)
    delete(hc.lay.x); delete(hc.lay.y)
    delete(hc.best_lay.x); delete(hc.best_lay.y)
    destroy_eval_scratch(&hc.eval)
}

init_hillclimber :: proc (hc: ^Hillclimber, modules: []Module) {
    n := len(modules)
    hc^ = {}
    hc.modules = modules
    hc.cur = make_state(n)
    hc.best = make_state(n)
    hc.lay = make_layout(n)
    hc.best_lay = make_layout(n)

    hc.eval = make_eval_scratch(.Murata, n)

    // pos = neg: every module left of the next, one horizontal row.
    for i in 0 ..< n {
        hc.cur.pos[i] = i
        hc.cur.neg[i] = i
    }

    // i added this because the sequence starting in a row lead to 85% solved for 200 modules
    rand.shuffle(hc.cur.neg)

    hc.restart_after = 100 * n

    evaluate(modules, hc.cur, &hc.lay, &hc.eval)
    hc.cur_cost = cost(hc.lay)
    hc.best_cost = hc.cur_cost
    copy_state(&hc.best, hc.cur)
    copy_layout(&hc.best_lay, hc.lay)
}



hillclimber :: proc(modules: []Module, time_limit: f64, evaluator: Evaluator) -> Result {
    hc: Hillclimber
    init_hillclimber(&hc, modules[:])
    defer destroy_hillcilmber(&hc)


    time_start := time.tick_now()
    hillclimb(&hc, time_limit, time_start)

    lay := Layout{
        x = slice.clone(hc.best_lay.x),
        y = slice.clone(hc.best_lay.y),
        w = hc.best_lay.w,
        h = hc.best_lay.h,
    }
    seq := State{
        pos     = slice.clone(hc.best.pos),
        neg     = slice.clone(hc.best.neg),
        rotated = slice.clone(hc.best.rotated),
    }

    return {lay, seq, hc.best_cost, time.duration_seconds(time.tick_since(time_start)), "Hillclimber"}

}

hillclimb :: proc(hc: ^Hillclimber, time_limit: f64, time_start: time.Tick) {
    CHECK_EVERY :: 1024
    for !hc.done {
        for _ in 0 ..< CHECK_EVERY {
            if hc.done do break
            hill_step(hc)
        }
        if time.duration_seconds(time.tick_since(time_start)) > time_limit {
            hc.done = true
        }
    }
    // we should consider reheating when it is done before time limit
    // or make the cooling schedule fit the time limit so it doesnt stop while hot
}


hill_step :: proc(hc: ^Hillclimber) {
    if hc.done do return

    // Divides current temperature change with total temperature change
    // progress := math.ln(an.t0 / an.temp) / math.ln(an.t0 / an.t_min)
    // mv := random_move(len(an.modules), progress)
    mv := random_move(len(hc.modules), 0) // TODO what should we do wrt progress

    apply_move(&hc.cur, mv)
    evaluate(hc.modules, hc.cur, &hc.lay, &hc.eval)
    c := cost(hc.lay)
    delta := c - hc.cur_cost

    // if delta <= 0 {
    if delta <= 0 {
        hc.cur_cost = c
        hc.accepted += 1
        if c < hc.best_cost {
            hc.best_cost = c
            copy_state(&hc.best, hc.cur)
            copy_layout(&hc.best_lay, hc.lay)
        }
    } else {
        apply_move(&hc.cur, mv) // undo
    }

    hc.total_moves += 1
    // hc.moves_at_temp += 1
    // if hc.moves_at_temp >= hc.moves_per_temp {
    //     hc.moves_at_temp = 0
    //     hc.temp *= hc.alpha
    //     if hc.temp < hc.t_min do hc.done = true
    // }
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

// progress goes from 0 (hot) to 1 (cold). As in the paper, pos-only swaps
// are favoured early and rotations late
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
// Sequence pair -> packing
// ---------------------------------------------------------------------------

dims :: proc(m: Module, rotated: bool) -> (w, h: int) {
    if rotated do return m.h, m.w
    return m.w, m.h
}

evaluate_n2 :: proc(modules: []Module, s: State, lay: ^Layout, rank_n: []int) {
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

Evaluator :: enum {
    Murata,
    Pisinger,
}

Eval_Scratch :: struct {
    kind: Evaluator,
    rank_n: []int,
}

evaluate :: proc(modules: []Module, s: State, lay: ^Layout, es: ^Eval_Scratch)  {
    switch es.kind {
    case .Murata:
        evaluate_n2(modules, s, lay, es.rank_n)
    case .Pisinger:
        fmt.println("Pisinger eval requested, not yet implemented")
    }
}

cost :: proc(lay: Layout) -> f64 {
    return f64(lay.w) * f64(lay.h)
}


// ---------------------------------------------------------------------------
// Simulated annealing
// ---------------------------------------------------------------------------

// make_eval_scratch :: proc(evaluator: Evaluator, n: int) -> Eval_Scratch {
//     return {evaluator , make([]int, n)}
// }

make_eval_scratch :: proc(kind: Evaluator, n: int) -> (es: Eval_Scratch) {
    es.kind = kind
    switch kind {
    case .Murata:       es.rank_n = make([]int, n)
    case .Pisinger: // pisinger arrays later
    }
    return
}

destroy_eval_scratch :: proc(sc: ^Eval_Scratch) {
    delete(sc.rank_n)
}

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
    // an.rank_n = make([]int, n)

    an.eval = make_eval_scratch(.Murata, n)



    // pos = neg: every module left of the next, one horizontal row.
    for i in 0 ..< n {
        an.cur.pos[i] = i
        an.cur.neg[i] = i
    }

    // i added this because the sequence starting in a row lead to 85% solved for 200 modules
    rand.shuffle(an.cur.neg)


    evaluate(modules, an.cur, &an.lay, &an.eval)
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
        evaluate(modules, an.cur, &an.lay, &an.eval)
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

    // cool down to 10000x smaller than start temp
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
    destroy_eval_scratch(&an.eval)
}

anneal_step :: proc(an: ^Annealer) {
    if an.done do return

    // Divides current temperature change with total temperature change
    progress := math.ln(an.t0 / an.temp) / math.ln(an.t0 / an.t_min)
    mv := random_move(len(an.modules), progress)

    apply_move(&an.cur, mv)
    evaluate(an.modules, an.cur, &an.lay, &an.eval)
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

anneal :: proc(an: ^Annealer, time_limit: f64, time_start: time.Tick) {
    CHECK_EVERY :: 1024
    for !an.done {
        for _ in 0 ..< CHECK_EVERY {
            if an.done do break
            anneal_step(an)
        }
        if time.duration_seconds(time.tick_since(time_start)) > time_limit {
            an.done = true
        }
    }
    // we should consider reheating when it is done before time limit
    // or make the cooling schedule fit the time limit so it doesnt stop while hot
}

simulated_annealing :: proc(modules: []Module, time_limit: f64, evaluator: Evaluator) -> Result {
    an: Annealer
    init_annealer(&an, modules[:])
    defer destroy_annealer(&an)


    time_start := time.tick_now()
    anneal(&an, time_limit, time_start)

    lay := Layout{
        x = slice.clone(an.best_lay.x),
        y = slice.clone(an.best_lay.y),
        w = an.best_lay.w,
        h = an.best_lay.h,
    }
    seq := State{
        pos     = slice.clone(an.best.pos),
        neg     = slice.clone(an.best.neg),
        rotated = slice.clone(an.best.rotated),
    }

    return {lay, seq, an.best_cost, time.duration_seconds(time.tick_since(time_start)), "Simulated annealing"}
}
