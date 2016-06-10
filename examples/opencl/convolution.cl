#define image_height 4096
#define image_width 4096
#define filter_height 17
#define filter_width 17

#define border_height ((filter_height/2)*2)
#define border_width ((filter_width/2)*2)
#define input_height (image_height + border_height)
#define input_width (image_width + border_width)

#define i_end min(block_size_y*tile_size_y+border_height, input_height)
#define j_end min(block_size_x*tile_size_x+border_width, input_width)

__kernel void convolution_kernel(__global float *output, __global float *input, __constant float *d_filter) {
    int ty = get_local_id(1);
    int tx = get_local_id(0);
    int by = get_group_id(1) * block_size_y * tile_size_y;
    int bx = get_group_id(0) * block_size_x * tile_size_x;

    //shared memory to hold all input data need by this thread block
    __local float sh_input[block_size_y*tile_size_y+border_height][block_size_x*tile_size_x+border_width];

    //load all input data needed by this thread block into shared memory
    #pragma unroll
    for (int i=ty; i<i_end; i+=block_size_y) {
        #pragma unroll
        for (int j=tx; j<j_end; j+=block_size_x) {
            #if ((image_height%(block_size_y*tile_size_y)!=0) || (image_width%(block_size_x*tile_size_x)!=0))
            int y = by+i;
            int x = bx+j;
            if (y < input_height && x < input_width) {
                sh_input[i][j] = input[y*input_width+x];
            }
            #else
                sh_input[i][j] = input[(by+i)*input_width + (bx+j)];
            #endif
        }
    }
    barrier(CLK_LOCAL_MEM_FENCE);

    //thread-local registers to hold local sums
    float sum[tile_size_y][tile_size_x];
    #pragma unroll
    for (int yi=0; yi<tile_size_y; yi++) {   
        #pragma unroll
        for (int xi=0; xi<tile_size_x; xi++) {
             sum[yi][xi] = 0.0f;
        }
    }

    //for each filter weight
    #pragma unroll
    for (int i=0; i < filter_height; i++) {
        #pragma unroll
        for (int j=0; j < filter_width; j++) {

            #pragma unroll
            for (int yi=0; yi<tile_size_y; yi++) {   
                #pragma unroll
                for (int xi=0; xi<tile_size_x; xi++) {
                    sum[yi][xi] += sh_input[ty+yi*block_size_y+i][tx+xi*block_size_x+j] * d_filter[i*filter_width+j];
                }
            }

        }
    }

    //store results to global memory
    #pragma unroll
    for (int yi=0; yi<tile_size_y; yi++) {   
        #pragma unroll
        for (int xi=0; xi<tile_size_x; xi++) {
            #if ((image_height%(block_size_y*tile_size_y)!=0) || (image_width%(block_size_x*tile_size_x)!=0))
            int y = by+ty+yi*block_size_y;
            int x = bx+tx+xi*block_size_x;
            if (y < image_height && x < image_width) {
                output[y * image_width + x] = sum[yi][xi];
            }
            #else
                output[(by+ty+yi*block_size_y) * image_width + bx+tx+xi*block_size_x] = sum[yi][xi];
            #endif
        }
    }

}

__kernel void convolution_naive(__global float *output, __global float *input, __constant float *d_filter) {
    int x = get_global_id(0);
    int y = get_global_id(1);
    int i, j;
    float sum = 0.0;

    if (y < image_height && x < image_width) {

        for (j = 0; j < filter_height; j++) {
            for (i = 0; i < filter_width; i++) {
                sum += input[(y + j) * input_width + (x + i)] * d_filter[j * filter_width + i];
            }
        }

        output[y * image_width + x] = sum;
    }
}

