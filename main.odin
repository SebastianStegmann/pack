package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:slice"
import "core:mem"

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


    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            if len(track.bad_free_array) > 0 {
                fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
                for entry in track.bad_free_array {
                    fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }




    container, modules, ok := load_instance(INSTANCE)

    if !ok do return
    defer delete(modules)

    time_limit: f64 = 0.1

    total_area := 0
    for m in modules do total_area += m.w * m.h

    // TODO: i think the time should be started inside the algorithm
    //       so when we do multiple runs the start is relative to the algorithm not main


    avg_time: f64
    avg_best_cost: f64
    // overall_best_cost: f64
    result: Result
    runs :: 10
    best_result: Result 
    defer destroy_result(&best_result)

    destroy_result :: proc(r: ^Result) {
        delete(r.best_lay.x)
        delete(r.best_lay.y)
        delete(r.best_seq.pos)
        delete(r.best_seq.neg)
        delete(r.best_seq.rotated)
    }


    for r in 0..<runs {
        result := simulated_annealing(modules[:], time_limit, .Murata)
        // result = hillclimber(modules[:], time_limit, .Murata)
        fmt.println(result.best_cost)
        avg_time += result.elapsed_time
        avg_best_cost += result.best_cost

        if result.best_cost < best_result.best_cost || r == 0 {
            destroy_result(&best_result)
            best_result = result
        } else {
            destroy_result(&result)
        }

    }

    fmt.println("Avg time: ", avg_time / runs)
    fmt.println("Avg best cost: ", avg_best_cost / runs)
    fmt.println("Best observed cost: ", best_result.best_cost)

    fmt.println("results:", best_result)

    visualize2D(modules[:], best_result, total_area)

}


// ---------------------------------------------------------------------------
// Load data
// ---------------------------------------------------------------------------


INSTANCE :: "data/ep2/ep2-30-W-R-25.2kp"

Container :: struct {
    w, h: int,
}

Module :: struct {
    id, w, h: int,
}

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

