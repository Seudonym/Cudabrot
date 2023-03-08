# Cudabrot
This repository contains a basic implementation of a Mandelbrot renderer written in CUDA C++. All the images below were taken within this program. Not possible to build the source yourself for now, unless you setup Imgui with SFML yourself. [For more details.](https://github.com/SFML/imgui-sfml)


## Features
- Renders in realtime on the GPU (Assuming its compatible)
- Supports both floating and double precision (double is understandably slower)
- Brightness and contrast settings to produce wallpaper quality images
- Two different coloring functions (Naive linear iteration based and Stripe average coloring)

## Screenshots
![](https://github.com/Seudonym/Cudabrot/blob/main/IMg2.png)
![](https://github.com/Seudonym/Cudabrot/blob/main/IMG.png)
![](https://github.com/Seudonym/Cudabrot/blob/main/IMG4.bmp)
![](https://github.com/Seudonym/Cudabrot/blob/main/IMG.bmp)

## Controls
- W,A,S,D to move
- [ and ] to zoom in and out 
- LShift and LCtrl to increase and decrease iteration count
- O to output the image into a bmp(can be changed to png)
- P to print debug info
- GUI controls are straight-forward
