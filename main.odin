package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

INSTANCE :: "data/ep2/ep2-30-W-R-25.2kp"

Container :: struct {
    w, h: int,
}

Module :: struct {
    id, w, h: int,
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
load_instance :: proc(path: string) -> (container: Container, modules: [dynamic]Module, ok: bool) {
    data, err := os.read_entire_file(path, context.allocator)
    if err != nil {
        fmt.eprintln("could not read", path, err)
        return
    }
    defer delete(data)

    it := string(data)

    // skip container
    c : string
    c ,_ = strings.split_lines_iterator(&it)
    c_split := strings.split(c, ", ")
    defer delete(c_split)

    container = Container{field(c_split, 1), field(c_split, 2)}

    for line in strings.split_lines_iterator(&it) {

        // assumes every file is formatted correctly
        parts := strings.split(line, ", ")
        defer delete(parts)

        m := Module{field(parts, 1), field(parts, 2), field(parts, 3)}
        append(&modules, m)
    }
    return container, modules, len(modules) >= 2
}

// ---------------------------------------------------------------------------
// Main
// Takes INSTANCE, gets the modules (and in the future the container)
// Gives modules and time limit to algorithm
// Returns Result and passes it to visualizer
// ---------------------------------------------------------------------------


Result :: struct {
    best_lay: Layout,
    best_seq: State,
    best_cost: f64,
    elapsed_time: f64,
    algorithm: string,
}

//TODO : add a way to do multiple runs, possibly with different algorithms, calculating averages etc

main :: proc() {
    container, modules, ok := load_instance(INSTANCE)

    if !ok do return
    defer delete(modules)

    time_limit: f64 = 0.1

    total_area := 0
    for m in modules do total_area += m.w * m.h

    // TODO: i think the time should be started inside the algorithm
    //       so when we do multiple runs the start is relative to the algorithm not main

    // results := simulated_annealing(modules[:], time_limit, .Murata)
    results := hillclimber(modules[:], time_limit, .Murata)


    fmt.println("results:", results)

    visualize2D(modules[:], results, total_area)
}
