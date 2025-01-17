/*
 * CUDA program to multiply matrices (fills in matrices itself)
 * 
 * compile with:
 *      nvcc -o matrix_multiply matrix_multiply.cu
 *
 * run with:
 *      ./matrix_multiply
 */

#include <stdio.h>
#include <cassert>
#include <cstdlib>

//constants to control the program:
#define NTESTS 1           /* # of tests to run */
#define TILE_WIDTH 32      /* # of threads in each dimension per block */
                           /* #threads per block = TILE_WIDTH * TILE_WIDTH */
#define WIDTH 1024         /* matrix dimensions (assumes square matrix) */


__global__ void kernel(float* Md, float* Nd, float* Pd, int width) {
  //method to run on GPU; called once per element of output matrix
  
  //calculate indices for the element to compute:
  int row = blockIdx.y*TILE_WIDTH + threadIdx.y;
  int col = blockIdx.x*TILE_WIDTH + threadIdx.x;

  if(row >= width || col >= width)  //check that indices are in bounds
    return;  

  float tmp = 0;  //local variable in which to accumulate the answer
  for(int k=0; k < width; ++k)
    tmp += Md[row*width + k] * Nd[k*width+col];
  Pd[row*width+col] =  tmp;
}

void verify_solution(float *a, float *b, float *c, int N) {
  //verify the solution on the CPU

  //threshold for matching: (0 ok since all vals are small ints)
  float epsilon = 0;  

  for (int i = 0; i < N; i++) {      //for every column...
    for (int j = 0; j < N; j++) {    //for every row in that column
      float tmp = 0;
      for (int k = 0; k < N; k++) {
        tmp += a[i * N + k] * b[k * N + j];
      }

    // Check against the GPU result, throw an error if not equal 
    assert(fabs(c[i * N + j] - tmp) <= epsilon);
    }
  }
}

void check(cudaError_t retVal) {
  //takes return value of a CUDA function and checks if it was an error

  if(retVal != cudaSuccess) {
    if (retVal==cudaErrorInvalidConfiguration)
      printf("Number of Threads per block is not valid");
    fprintf(stderr, "ERROR: %s\n", cudaGetErrorString(retVal));
    exit(1);
  }
}

float runTest (float* M, float* N, float* P, float* Md, float* Nd, float* Pd, int size) {
    
  //allocate timers
  cudaEvent_t start;
  check(cudaEventCreate(&start));
  cudaEvent_t stop;
  check(cudaEventCreate(&stop));
 
  //start timer
  check(cudaEventRecord(start,0));

  //transfer a and b to the GPU
  check(cudaMemcpy(Md, M, size, cudaMemcpyHostToDevice));
  check(cudaMemcpy(Nd, N, size, cudaMemcpyHostToDevice));

  //call the kernel
  int gridsize = (WIDTH+TILE_WIDTH-1)/TILE_WIDTH;
  dim3 dimGrid(gridsize, gridsize);
  dim3 dimBlock(TILE_WIDTH, TILE_WIDTH);
  kernel<<<dimGrid,dimBlock>>>(Md, Nd, Pd, WIDTH);

  //check if kernel encountered an error due to invalid configurations
  cudaError_t err = cudaGetLastError();
  check(err);

  //transfer result matrix to the host
  check(cudaMemcpy(P, Pd, size, cudaMemcpyDeviceToHost));

  //stop timer and store it
  check(cudaEventRecord(stop,0));
  check(cudaEventSynchronize(stop));
  float diff;
  check(cudaEventElapsedTime(&diff, start, stop));

  //deallocate timers
  check(cudaEventDestroy(start));
  check(cudaEventDestroy(stop));

  //print and return time
  printf("Time: %f ms\n", diff);
  return diff;
}

int main() {
  float* M;       //input arrays (on host)
  float* N;
  float* P;       //output array (on host)

  float* Md;      //input arrays (on device)
  float* Nd;
  float* Pd;      //output array (on device)
  
  int size = WIDTH * WIDTH * sizeof(float);  //size of matrix in bytes

  //allocate memory
  M = (float*) malloc(size);
  N = (float*) malloc(size);
  P = (float*) malloc(size);
  check(cudaMalloc((void**) &Md, size));
  check(cudaMalloc((void**) &Nd, size));
  check(cudaMalloc((void**) &Pd, size));

  //fill M and N arrays (all elements <= 2048 so results stay small)
  int cor=0;
  for(int i=0; i < WIDTH * WIDTH; i++){
    M[i] = N[i] = i-cor;
    if(i % 2048 == 0)
      cor=i;
  }

  float total_time = 0;  //accumultate execution times for averaging

  for(int i=0; i < NTESTS; i++)
    total_time += runTest(M, N, P, Md, Nd, Pd, size);

  printf("Avg for %d tests: %f ms and size of matrix %d\n",
	 NTESTS, total_time/(float)NTESTS, WIDTH);
  
  verify_solution(M,N,P,WIDTH);  //verify result 

  //free all memory:
  free(M);
  free(N);
  free(P);
  check(cudaFree(Md));
  check(cudaFree(Nd));
  check(cudaFree(Pd));
}
