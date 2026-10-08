package main

import rl "vendor:raylib"

import "core:math/rand"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"

Container :: struct {
    w, h, d: u64
}

Module :: struct {
    id: u64,
    w, h, d: u64,
    p: u64,

}

getData :: proc(filepath: string) -> (Container, [dynamic]Module) {
    data, err := os.read_entire_file(filepath, context.allocator)
/*    if (err != nil) {
        return nil, nil
    }
*/    
    defer delete(data, context.allocator)

    it := string(data)

    first := true
    modules := make([dynamic]Module)
    container: Container

    for line in strings.split_lines_iterator(&it) {
        splitParts := strings.split(line, ", ")

        if first {  
            container.w, _ = strconv.parse_u64(splitParts[1])
            container.h, _ = strconv.parse_u64(splitParts[2])     
            container.d, _ = strconv.parse_u64(splitParts[3])

            first = false
            continue
        }

        id, _ := strconv.parse_u64(splitParts[1])
        w, _ := strconv.parse_u64(splitParts[2])
        h, _ := strconv.parse_u64(splitParts[3])     
        d, _ := strconv.parse_u64(splitParts[4])
        p, _ := strconv.parse_u64(splitParts[5])

        append_elem(&modules, Module{id, w, h, d, p})

    }

    return container, modules
}


transform :: proc(size: [3]u64, pos: [3]u64) -> [3]f32 {

    result : [3]f32 = {0,0,0}

    for i in 0..<3 {
        result[i] = f32(pos[i]) + f32(size[i]) / 2
    }

    return result
}




main :: proc() {
    container, modules := getData("data/ep3/ep3-20-C-C-50.3kp")

    fmt.println(transform({container.w, container.h, container.d}, {0,0,0}))

    // fmt.println(container, modules)
    // algorithm

    // algorithm result
    positive := [6]int{0,1,3,2,4,5}
    negative := [6]int{0,2,4,1,3,5}
    third    := [6]int{0,2,4,1,3,5}

    // visualize
    // fmt.println(modules[0].id)

    for i in positive {
        // visualize each
        fmt.println(modules[i].id)

        // figure out coordinates based on sequence pairs


        // check collision with other modules and container

    }

    // display
    


    startTime := rl.GetTime()

    transformedContainer := transform({container.w, container.h, container.d}, {0,0,0})

    camera := rl.Camera3D {
        position = {400, 100, 400},
        target = transformedContainer,
        up = {0, 400, 0},
        fovy = 45,
        projection = rl.CameraProjection.PERSPECTIVE,
    }



    rl.InitWindow(800, 600, "3D Box")
    defer rl.CloseWindow()

    for !rl.WindowShouldClose() {
        rl.UpdateCamera(&camera, .ORBITAL)
        rl.SetTargetFPS(60)

        elapsed := rl.GetTime() - startTime

        rl.BeginDrawing()

        defer  rl.EndDrawing()

        rl.ClearBackground(rl.RAYWHITE)

        rl.BeginMode3D(camera)

        rl.DrawCube(
            {10, 10, 10},
            20,
            20,
            20,
            rl.BLUE
        )

        rl.DrawCubeWires(
            {10, 10, 10},
            20,
            20,
            20,
            rl.BLACK,
        )

        

        fmt.println(transformedContainer)
        rl.DrawCubeWires(
                transformedContainer,
                f32(container.w),
                f32(container.h),
                f32(container.d),
                rl.BLACK,
            )


        rl.DrawGrid(2000, 1)

        rl.EndMode3D()

        rl.DrawFPS(10, 10)      
}
}

/*
    /*

    coloredBoxes := make([dynamic]coloredBox)

    

    for box in boxes {
        append_elem(&coloredBoxes, makeCBoxes(box))
    }

    startTime := rl.GetTime()

    
   
    for !rl.WindowShouldClose() {
        rl.UpdateCamera(&camera, .ORBITAL)
        rl.SetTargetFPS(60)

        elapsed := rl.GetTime() - startTime

         boxesToShow := int(elapsed * 2)

        if boxesToShow > len(coloredBoxes) {
            boxesToShow = len(coloredBoxes)
        }

        rl.BeginDrawing()

        defer  rl.EndDrawing()

        rl.ClearBackground(rl.RAYWHITE)

        rl.BeginMode3D(camera)

         for i := 0; i < boxesToShow; i += 1 {
            cb := coloredBoxes[i]
            b := cb.box

            rl.DrawCube(
                {b.x, b.y, b.z},
                b.width,
                b.height,
                b.length,
                cb.color,
            )

            rl.DrawCubeWires(
                {b.x, b.y, b.z},
                b.width,
                b.height,
                b.length,
                rl.BLACK,
            )
        }

        container := moveContainer(CONTAINER)

        rl.DrawCubeWires(
                container.a,
                container.b,
                container.c,
                container.d,
                rl.BLACK,
            )

        // for cb in coloredBoxes {
        //     b := cb.box
        //     rl.DrawCube({b.x, b.y, b.z}, b.width, b.height, b.length, cb.color)
        //     rl.DrawCubeWires({b.x, b.y, b.z}, b.width, b.height, b.length, rl.BLACK)
        // }

        rl.DrawGrid(20, 1)

        rl.EndMode3D()

        rl.DrawFPS(10, 10)      
    }
        */
        */
