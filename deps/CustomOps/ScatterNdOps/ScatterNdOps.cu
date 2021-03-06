#include "cuda.h"
#include <stdio.h>
__global__ void ScatterNdOps_forward_kernel(double *out, const long long*ii, const double *update, int n){
    int p =  blockIdx.x *blockDim.x + threadIdx.x;
    if (p<n){
        out[ii[p]-1] = update[p];
    }
}

__global__ void setzero_kernel(double *out, int n){
    int p =  blockIdx.x *blockDim.x + threadIdx.x;
    if (p<n){
        out[p] = 0.0;
    }
}

void Gpu_ScatterNdOps_forward(double *out, const long long *ii,
    const double *update, int n, int N){
    setzero_kernel<<< (N - 1)/64 + 1, 64 >>>(out, N);
    ScatterNdOps_forward_kernel<<< (n - 1)/64 + 1, 64 >>>(out, ii, update, n);
 }

 
 __global__ void ScatterNdOps_backward_kernel(double *grad_update, 
    const double *grad_out,
    const double *out, const long long *ii,
    const double *update, int n){
    int p =  blockIdx.x *blockDim.x + threadIdx.x;
    if (p<n) {
        grad_update[p] = grad_out[ii[p]-1];
    }
}

void Gpu_ScatterNdOps_backward(
    double *grad_update, 
    const double *grad_out,
    const double *out, const long long *ii,
    const double *update, int n){
    setzero_kernel<<< (n - 1)/64 + 1, 64 >>>(grad_update, n);
    ScatterNdOps_backward_kernel<<< (n - 1)/64 + 1, 64 >>>(grad_update, grad_out, out, ii, update, n);
 }

 void get_ScatterNdOps_num(long long *out, const long long *m){
    cudaMemcpy(out, m, sizeof(long long), cudaMemcpyDeviceToHost);
 }