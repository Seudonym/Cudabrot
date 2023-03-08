#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <stdio.h>
#include <cmath>
#include <fstream>

#include <SFML/Graphics.hpp>

#include "imgui.h"
#include <imgui-SFML.h>

//#define DOUBLE_PRECISION
#ifdef DOUBLE_PRECISION
typedef double data;
#else
typedef float data;
#endif

// Complex struct
struct Complex {
	data x, y;
	__device__ Complex() {x = 0.; y = 0.;}
	__device__ Complex(data _x, data _y) { x = _x; y = _y; }
	__device__ Complex operator+(const Complex& other) { return Complex(x + other.x, y + other.y); }
	__device__ Complex operator*(const Complex& other) { return Complex(x * other.x - y * other.y, x * other.y + y * other.x); }
};

// Typedefs and constants
typedef unsigned int uint;
typedef uint8_t u8;

const int WIDTH = 1920;
const int HEIGHT = 1024;

data cx = -0.251645; data cy = -0.768400;
data zoom = 1.0;
data expfactor = 0.0;
data max_iterations = 300.0;

// Function declarations
cudaError_t populate_buffer(data* params, uint params_size, data max_iterations, uint* color_buffer);
__device__ uint encode_rgb(u8 r, u8 g, u8 b); 

// OG mandelbrot with linear grayscale coloring
__global__ void mandelbrot(data* params, data max_iterations, uint* color_buffer) {
	int x = blockIdx.x * blockDim.x + threadIdx.x;
	int y = blockIdx.y * blockDim.y + threadIdx.y;

	data min_x = params[0];
	data max_x = params[1];
	data min_y = params[2];
	data max_y = params[3];

	data cx = min_x + x * (max_x - min_x) / (WIDTH - 1);
	data cy = min_y + y * (max_y - min_y) / (HEIGHT - 1);

	Complex c(cx, cy);
	Complex z = c;

	data iterations = 0; 

	while (iterations < max_iterations && z.x * z.x + z.y * z.y < 4.0) {
		z = z * z + c;
		iterations += 1.0;
	}
	uint r, g, b;
	if (iterations < max_iterations) {
		data frac = 1.0 + log2((log(16.0) / log(z.x * z.x + z.y * z.y)));

		r = (0.5 * sin(frac) + 0.5) * 255;
		g = (r * frac) / 255;
		b = frac * 255;
	} else {r = g = b = 0;}
	uint color = encode_rgb(r, g, b);

	color_buffer[x + y * WIDTH] = color;
}

__device__ data map(data x) {
	return cos(x);
}

__device__ data gamma(data x, data c, data b) {
	/*data a = 4 * pow(x, 3.0);
	data b = 4 * pow(x - 1, 3.0) + 1;
	if (x < 0.5) return a;
	return b;*/
	data col = 0.5 + (x - 0.5) * c + b;
	if (col < 0.0) return 0.0;
	else if (col > 1.0) return 1.0;
	return col;
}

// Stripe average coloring function
__global__ void mandelbrot1(data* params, data max_iterations, uint* color_buffer) {
	int x = blockIdx.x * 32 + threadIdx.x;
	int y = blockIdx.y * 32 + threadIdx.y;

	data min_x = params[0];
	data max_x = params[1];
	data min_y = params[2];
	data max_y = params[3];

	data cx = min_x + x * (max_x - min_x) / (WIDTH - 1);
	data cy = min_y + y * (max_y - min_y) / (HEIGHT - 1);

	Complex c(cx, cy);
	Complex z;

	


	Complex last_z;
	data avg = 0.0;
	data last_added = 0.0;
	data stripe_density = 5.0;
	data skip = 0;
	data count = 0;
	data escape_radius = 10000.0;

	data i = 0.0;
	while (i < max_iterations) {
		
		z = z * z + c;
		if (i >= skip) {
			count += 1.0;
			last_added = 0.5 + 0.5 * sin(stripe_density * atan2(z.y, z.x));
			avg += last_added;
		}
		
		if (z.x * z.x + z.y * z.y > escape_radius * escape_radius && i > skip) break;
		last_z = z;
		i = i + 1.0;
	}
	data prev_avg = (avg - last_added) / (count - 1.0);
	avg = avg / count;
	data frac = 1.0 + log2((log(escape_radius * escape_radius) / log(z.x * z.x + z.y * z.y)));

	data mix = frac * avg + (1.0 - frac) * prev_avg;

	uint r, g, b;
	if (i < max_iterations) {
		data dr, dg, db;
		dr = (0.5 + 0.5 * map(mix * 3.14 + params[4]));
		dg = (0.5 + 0.5 * map(mix * 3.14 + params[5]));
		db = (0.5 + 0.5 * map(mix * 3.14 + params[6]));

		b = gamma(dg, params[7], params[8]) * 255;
		g = gamma(dr, params[7], params[8]) * 255;
		r = gamma(db, params[7], params[8]) * 255;
	}
	else {
		r = g = b = 0;
	}
	uint color = encode_rgb(r, g, b);

	color_buffer[x + y * WIDTH] = color;
}

/*
	Parameters:
	0	-> Minimum X
	1	-> Maximum X
	2	-> Minimum Y
	3	-> Maximum Y
	4	-> R slider for stripe coloring
	5	-> G
	6	-> B
*/

int main() {
	data* params;
	uint* color_buffer;

	color_buffer = new uint[WIDTH * HEIGHT];
	params = new data[8];


	data aspect = WIDTH * 1.0 / HEIGHT;

	params[0] = cx - zoom * 2 * aspect;
	params[1] = cx + zoom * 2 * aspect;
	params[2] = cy - zoom * 2;
	params[3] = cy + zoom * 2;
	params[4] = -3.4;
	params[5] = 7.35;
	params[6] = 2.4;
	params[7] = 1.0;

	data movement_speed = 0.1;
	data zoom_speed = 3.;
	sf::RenderWindow window(sf::VideoMode(WIDTH, HEIGHT), "Test Window");
	sf::Image image;
	sf::Texture texture;
	sf::Sprite sprite;
	sf::Event event;
	sf::Clock deltaClock;

	bool render_new = false;

	image.create(WIDTH, HEIGHT);

	ImGui::SFML::Init(window);

	
	while (window.isOpen()) {
		while (window.pollEvent(event)) {
			ImGui::SFML::ProcessEvent(window, event);
			if (event.type == sf::Event::Closed) window.close();

			if (event.type == sf::Event::KeyPressed) {
				render_new = true;
				if (event.key.code == sf::Keyboard::W) {
					cy -= movement_speed * zoom ;
				}
				if (event.key.code == sf::Keyboard::S) {
					cy += movement_speed * zoom ;
				}
				if (event.key.code == sf::Keyboard::A) {
					cx -= movement_speed * zoom;
				}
				if (event.key.code == sf::Keyboard::D) {
					cx += movement_speed * zoom;
				}
				if (event.key.code == sf::Keyboard::LShift) max_iterations += 10;
				if (event.key.code == sf::Keyboard::LControl) max_iterations -= 10;
				if (event.key.code == sf::Keyboard::P) {
					printf("X: %lf\n", cx);
					printf("Y: %lf\n", cy);
					printf("Zoom: %lf\n", 1/zoom);
					printf("Iterations: %lf\n", max_iterations);
				}
				if (event.key.code == sf::Keyboard::O) {
					image.saveToFile("IMG.bmp");
				}

				if (event.key.code == sf::Keyboard::LBracket) expfactor += 0.02 * zoom_speed;
				if (event.key.code == sf::Keyboard::RBracket) expfactor -= 0.02 * zoom_speed;

				zoom = pow(2.0, expfactor);
				params[0] = cx - zoom * 2 * aspect;
				params[1] = cx + zoom * 2 * aspect;
				params[2] = cy - zoom * 2;
				params[3] = cy + zoom * 2;
			}
		}
		
		if (render_new) {
			populate_buffer(params, 9, max_iterations, color_buffer);
		
			for (int y = 0; y < HEIGHT; y++) for (int x = 0; x < WIDTH; ++x) {
				int idx = x + y * WIDTH;
				uint color = color_buffer[idx];
				image.setPixel(x, y, sf::Color(color));
			}
		
			texture.loadFromImage(image);
			texture.setSmooth(true);
			sprite.setTexture(texture);
		}
		window.clear();
		window.draw(sprite);

		ImGui::SFML::Update(window, deltaClock.restart());

		ImGui::Begin("Hello");
		ImGui::SetWindowFontScale(1.8);

#ifndef DOUBLE_PRECISION 
		ImGui::InputFloat("R", &params[4], 0.05f);
		ImGui::InputFloat("G", &params[5], 0.05f);
		ImGui::InputFloat("B", &params[6], 0.05f);
		ImGui::InputFloat("Contrast", &params[7], 0.05f);
		ImGui::InputFloat("Brightness", &params[8], 0.05f);
#else
		ImGui::InputDouble("R", &params[4], 0.05);
		ImGui::InputDouble("G", &params[5], 0.05);
		ImGui::InputDouble("B", &params[6], 0.05);
#endif
		ImGui::End();
		
		ImGui::SFML::Render(window);
		window.display();
		//render_new = false;
	}

	ImGui::SFML::Shutdown();

	return 0;
}


cudaError_t populate_buffer(data* params, uint params_size, data max_iterations, uint* color_buffer) {
	uint* dev_color_buffer;
	data* dev_params;
	cudaError_t cudaStatus;

	uint size = WIDTH * HEIGHT;

	// Allocate color buffer on the device
	cudaStatus = cudaMalloc((void**)&dev_color_buffer, size * sizeof(uint));
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMalloc failed!\n");
		cudaFree(dev_color_buffer);
		return cudaStatus;
	}
	
	// Allocate params on device
	cudaStatus = cudaMalloc((void**)&dev_params, params_size * sizeof(data));
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMalloc failed!\n");
		cudaFree(dev_params);
		cudaFree(dev_color_buffer);
		return cudaStatus;
	}

	// Copy params to dev_params
	cudaStatus = cudaMemcpy(dev_params, params, params_size * sizeof(data), cudaMemcpyHostToDevice);
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "params copy failed!\n");
		cudaFree(dev_color_buffer);
		cudaFree(dev_params);
		return cudaStatus;
	}

	dim3 threads_per_block = dim3(32, 32);
	dim3 blocks_per_grid = dim3(WIDTH / 32, HEIGHT / 32);


	mandelbrot1 <<< blocks_per_grid, threads_per_block >>> (dev_params, max_iterations, dev_color_buffer);
	
	cudaStatus = cudaMemcpy(color_buffer, dev_color_buffer, size * sizeof(uint), cudaMemcpyDeviceToHost);
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaMemcpy failed!");
		cudaFree(dev_color_buffer);
		return cudaStatus;
	}
	cudaFree(dev_color_buffer);
	cudaFree(dev_params);
}

__device__ uint encode_rgb(u8 r, u8 g, u8 b) {
	uint color = 0x00;
	color += r;
	color <<= 8;
	color += g;
	color <<= 8;
	color += b;
	color <<= 8;
	color += 0xff;

	return color;
}