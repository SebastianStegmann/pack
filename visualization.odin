package main

import "core:fmt"
import rl "vendor:raylib"

visualize2D :: proc(modules: []Module, results: Result, total_area: int) {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT})
    rl.SetTraceLogLevel(.WARNING)
    rl.InitWindow(1200, 900, fmt.ctprintf("Visualizer – %s", results.algorithm))
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    for !rl.WindowShouldClose() {

        lay := results.best_lay
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
            w, h := dims(m, results.best_seq.rotated[i])
            r := rl.Rectangle{
                ox + f32(lay.x[i]) * scale,
                oy + f32(lay.y[i]) * scale,
                f32(w) * scale,
                f32(h) * scale,
            }
            rl.DrawRectangleRec(r, rl.ColorFromHSV(f32(i) * 360 / 20, 0.45, 0.95))
            rl.DrawRectangleLinesEx(r, 1, rl.DARKGRAY)
            // add number if big enough
            if r.width > 14 && r.height > 12 {
                rl.DrawText(fmt.ctprintf("%d", i), i32(r.x) + 3, i32(r.y) + 2, 10, rl.BLACK)
            }
        }

        // Chip outline
        rl.DrawRectangleLinesEx(
            {ox, oy, f32(lay.w) * scale, f32(lay.h) * scale},
            2, rl.RED,
        )

        rl.DrawText(
            fmt.ctprintf("chip %d x %d = %d  |  module area %d | elapsed_time %.1f",
                lay.w, lay.h, lay.w * lay.h, total_area, results.elapsed_time),
            margin, 15, 20, rl.BLACK,
        )

        rl.EndDrawing()
        free_all(context.temp_allocator)
    }
}
