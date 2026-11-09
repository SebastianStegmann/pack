# Sequence-Based Packing

# Packing

Code for our 3D packing project at Roskilde University. The goal is to place rectangular boxes in a single container so that the total profit of the packed boxes is as high as possible. Boxes can't overlap and keep their given orientation. This is the 3D knapsack packing problem (3DKP), and it is NP-hard.


## Usage

The project is written in [Odin](https://odin-lang.org/). Install the Odin compiler first, then run these commands from the repo root:

```sh
# build and run
odin run .

# optimized build
odin build . -o:speed
./3d-packing
```

## Data

We use the test instances from J. Egeblad and D. Pisinger, *Heuristic approaches for the two- and three-dimensional knapsack packing problem*, Computers & Operations Research 36 (2009), 1026–1049.

Download the instances (zip) from David Pisinger's page: https://hjemmesider.diku.dk/~pisinger/codes.html

Unzip them into a `data/` folder in the repo root.