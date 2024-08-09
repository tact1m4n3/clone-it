# Clone it!
> Do you have some free time? Do you want to exercise your mind in a fun way? Be sure to try our puzzle game, "Clone it"!

## Build and Run
- Debug build
```sh
zig build run
```
- Release build
```sh
zig build -Doptimize=ReleaseSafe run
```
- Run platform specific build in the [build](build/) directory
    - Make sure to copy the [assets](assets/) directory (from the project root) to the same directory as the executable

## Inspiration
Monument Valley is a great mobile puzzle game exploring the idea of non-euclidean geometry. It inspired us to come up with a fascinating idea to explore for ourselves: clones, though we barely scratched the surface of it. Moreover, Monument Valley inspired our game's art style: flat shading and an isometric camera.

## What it is about
It encompasses multiple puzzles. The goal is to place each clone on its corresponding tile with the same color. You can move using arrows, "wasd" or by swiping on the screen. "t" issues a teleport command, which means all players on a teleport block (of blue color) will teleport to a corresponding blue-colored block. A traversable portal emits particles. Non-traversable portals are enabled by pressing a button (moving to a button block of pink color). What button activates a given portal and the pair of blocks that make up a portal are not specified, though they are deducible. An unpressed button emits particles similarly to an activated portal. Some buttons may not stay pressed without a clone standing on them! Beware that all actions apply to all clones at once.

## How we built it and what we learned
The project is made using Zig and OpenGL. Zig is a relatively new programming language that we weren't that familiar with. Throughout this experience, we learned a lot about Zig, and we look forward to using it in other projects as well.

## Challenges we ran into
Not being that familiar with Zig, we had some challenges in the project organization department. Each language has its own way of doing things. We tried to follow Zig's idioms as much as we could.

## To do
- [x] Making a proof of concept.
- [ ] Finishing the game.
  - [ ] Adding more game mechanics.
  - [ ] Improving graphics and making them more expressive.
  - [ ] Writing more levels.
