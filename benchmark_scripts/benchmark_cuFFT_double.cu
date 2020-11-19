//general parts
#include <stdio.h>
#include <vector>
#include <memory>
#include <string.h>
#include <chrono>
#include <thread>
#include <iostream>

//CUDA parts
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <cufft.h>

#define GROUP 1


void launch_benchmark_cuFFT_double(bool file_output, FILE* output)
{

	const int num_runs = 3;
	if (file_output)
		fprintf(output, "1 - cuFFT FFT + iFFT C2C benchmark 1D batched in double precision\n");
	printf("1 - cuFFT FFT + iFFT C2C benchmark 1D batched in double precision\n");
	double benchmark_result[2] = { 0,0 };//averaged result = sum(system_size/iteration_time)/num_benchmark_samples
	cufftDoubleComplex* inputC = (cufftDoubleComplex*)malloc((uint64_t)sizeof(cufftDoubleComplex) *pow(2, 27));
	for (uint64_t i = 0; i <pow(2, 27); i++) {
		inputC[i].x = 2 * ((double)rand()) / RAND_MAX - 1.0;
		inputC[i].y = 2 * ((double)rand()) / RAND_MAX - 1.0;
	}
	for (int n = 0; n < 21; n++) {
		double run_time[num_runs][2];
		for (int r = 0; r < num_runs; r++) {
			cufftHandle planZ2Z;
			cufftDoubleComplex* dataC;

			uint32_t dims[3];
			dims[0] = 32 * pow(2, n); //Multidimensional FFT dimensions sizes (default 1). For best performance (and stability), order dimensions in descendant size order as: x>y>z.   
			if (n == 0) dims[0] = 2048;
			dims[1] = 64 * 32 * pow(2, 15) / dims[0];
			//dims[1] = (dims[1] > 32768) ? 32768 : dims[1];
			if (dims[1] == 0) dims[1] = 1;
			dims[2] = 1;
			cudaMalloc((void**)&dataC, sizeof(cufftDoubleComplex) * dims[0] * dims[1] * dims[2]);

			cudaMemcpy(dataC, inputC, sizeof(cufftDoubleComplex) * dims[0] * dims[1] * dims[2], cudaMemcpyHostToDevice);
			if (cudaGetLastError() != cudaSuccess) {
				fprintf(stderr, "Cuda error: Failed to allocate\n");
				return;
			}
			uint64_t sizeCUDA;
			switch (1) {
			case 1:
				cufftPlan1d(&planZ2Z, dims[0], CUFFT_Z2Z, dims[1]);
				cufftEstimate1d(dims[0], CUFFT_Z2Z, 1, &sizeCUDA);
				break;
			case 2:
				cufftPlan2d(&planZ2Z, dims[1], dims[0], CUFFT_Z2Z);
				cufftEstimate2d(dims[1], dims[0], CUFFT_Z2Z, &sizeCUDA);
				break;
			case 3:
				cufftPlan3d(&planZ2Z, dims[2], dims[1], dims[0], CUFFT_Z2Z);
				cufftEstimate3d(dims[2], dims[1], dims[0], CUFFT_Z2Z, &sizeCUDA);
				break;
			}

			double totTime = 0;
			uint64_t cuBufferSize = sizeof(double) * 2 * dims[0] * dims[1] * dims[2];
			uint64_t batch = ((4096 * 1024.0 * 1024.0) / cuBufferSize > 1000) ? 1000 : (4096 * 1024.0 * 1024.0) / cuBufferSize ;
			if (batch == 0) batch = 1;
			auto timeSubmit = std::chrono::steady_clock::now();
			for (int i = 0; i < batch; i++) {

				cufftExecZ2Z(planZ2Z, dataC, dataC, 1);
				cufftExecZ2Z(planZ2Z, dataC, dataC, -1);
			}
			cudaDeviceSynchronize();
			auto timeEnd = std::chrono::steady_clock::now();
			totTime = (std::chrono::duration_cast<std::chrono::microseconds>(timeEnd - timeSubmit).count() * 0.001) / batch;
			run_time[r][0] = totTime;
			if (n > 0) {
				if (r == num_runs - 1) {
					double std_error = 0;
					double avg_time = 0;
					for (uint32_t t = 0; t < num_runs; t++) {
						avg_time += run_time[t][0];
					}
					avg_time /= num_runs;
					for (uint32_t t = 0; t < num_runs; t++) {
						std_error += (run_time[t][0] - avg_time) * (run_time[t][0] - avg_time);
					}
					std_error = sqrt(std_error / num_runs);
					if (file_output)
						fprintf(output, "cuFFT System: %d %dx%d Buffer: %d MB avg_time_per_step: %0.3f ms std_error: %0.3f batch: %d benchmark: %d\n", (int)log2(dims[0]), dims[0], dims[1], cuBufferSize / 1024 / 1024, avg_time, std_error, batch, (int)(((double)cuBufferSize * sizeof(float) / sizeof(double) / 1024) / avg_time));

					printf("cuFFT System: %d %dx%d Buffer: %d MB avg_time_per_step: %0.3f ms std_error: %0.3f batch: %d benchmark: %d\n", (int)log2(dims[0]), dims[0], dims[1], cuBufferSize / 1024 / 1024, avg_time, std_error, batch, (int)(((double)cuBufferSize * sizeof(float) / sizeof(double) / 1024) / avg_time));
					benchmark_result[0] += ((double)cuBufferSize * sizeof(float)/sizeof(double)/ 1024) / avg_time;
				}

			}
			cufftDestroy(planZ2Z);
			cudaFree(dataC);
			cudaDeviceSynchronize();
			//cufftDoubleComplex* output_cuFFT = (cufftDoubleComplex*)(malloc(sizeof(cufftDoubleComplex) * dims[0] * dims[1] * dims[2]));
			//cudaMemcpy(output_cuFFT, dataC, sizeof(cufftDoubleComplex) * dims[0] * dims[1] * dims[2], cudaMemcpyDeviceToHost);
			//cudaDeviceSynchronize();


		}
	}
	free(inputC);
	benchmark_result[0] /= (21 - 1);
	if (file_output)
		fprintf(output, "Benchmark score cuFFT: %d\n", (int)(benchmark_result[0]));
	printf("Benchmark score cuFFT: %d\n", (int)(benchmark_result[0]));

}
