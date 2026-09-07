package main

import rl "vendor:raylib"

import "core:math/rand"


box :: struct {
    x, y, z: f32,
    width, height, length: f32
}

boxes := []box{
    // x,   y,   z,    width, height, length
    {0,   0,   0,     1,    1,      1},
    {1,   0,   0,     1,    1,      1},
    {0,   0,   1,     1,    1,      1},
    {1,   0,   1,     1,    1,      1},
    {2,   0,   2,     1,    1,      1},
}

coloredBox :: struct {
    box: box,
    color: rl.Color
}

main :: proc() {
    rl.InitWindow(800, 600, "3D Box")
    defer rl.CloseWindow()


    camera := rl.Camera3D {
        position = {0, 6, 10},
        target = {0, 1, 0},
        up = {0, 1, 0},
        fovy = 45,
        projection = rl.CameraProjection.PERSPECTIVE,
    }


    coloredBoxes := make([dynamic]coloredBox)

    makeCBoxes :: proc (b: box) -> coloredBox {
        modB := b

        modB.x = b.x + b.width /2
        modB.y = b.y + b.height /2
        modB.z = b.z + b.length /2

        return coloredBox{
            box = modB,
            color = rl.Color{u8(rand.int_max(255)), u8(rand.int_max(255)), u8(rand.int_max(255)), 255} }
    }


   


    for box in boxes {
        append_elem(&coloredBoxes, makeCBoxes(box))
    }

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.RAYWHITE)

        rl.BeginMode3D(camera)

        for cb in coloredBoxes {
            b := cb.box
            rl.DrawCube({b.x, b.y, b.z}, b.width, b.height, b.length, cb.color)
            rl.DrawCubeWires({b.x, b.y, b.z}, b.width, b.height, b.length, rl.BLACK)
        }

        rl.DrawGrid(10, 1)

        rl.EndMode3D()

        rl.EndDrawing()
    }
}