#include <dlfcn.h>
#include <android/log.h>
#include <mutex>
#include <cstdint>
#include <cstddef>
#include <cstdio>
#include <unistd.h>
#include <sys/stat.h>
#include <string>
#include <vector>

#define LOG_TAG "OpenCLLoader"

// OpenCL basic types
typedef int32_t cl_int;
typedef uint32_t cl_uint;
typedef uint64_t cl_ulong;
typedef uint64_t cl_bitfield;
typedef cl_bitfield cl_device_type;
typedef cl_uint cl_platform_info;
typedef cl_uint cl_device_info;
typedef cl_bitfield cl_command_queue_properties;
typedef intptr_t cl_context_properties;
typedef cl_uint cl_channel_order;
typedef cl_uint cl_channel_type;
typedef cl_bitfield cl_mem_flags;
typedef cl_uint cl_mem_object_type;
typedef cl_uint cl_buffer_create_type;
typedef cl_uint cl_program_info;
typedef cl_uint cl_program_build_info;
typedef cl_uint cl_kernel_work_group_info;
typedef uint64_t cl_mem_properties;
typedef cl_uint cl_bool;
typedef cl_bitfield cl_map_flags;
typedef cl_uint cl_profiling_info;
typedef cl_uint cl_queue_properties;

typedef struct _cl_platform_id *    cl_platform_id;
typedef struct _cl_device_id *      cl_device_id;
typedef struct _cl_context *        cl_context;
typedef struct _cl_command_queue *  cl_command_queue;
typedef struct _cl_mem *            cl_mem;
typedef struct _cl_program *        cl_program;
typedef struct _cl_kernel *         cl_kernel;
typedef struct _cl_event *          cl_event;

typedef struct _cl_image_format {
    cl_channel_order image_channel_order;
    cl_channel_type  image_channel_data_type;
} cl_image_format;

typedef struct _cl_image_desc {
    cl_mem_object_type image_type;
    size_t             image_width;
    size_t             image_height;
    size_t             image_depth;
    size_t             image_array_size;
    size_t             image_row_pitch;
    size_t             image_slice_pitch;
    cl_uint            num_mip_levels;
    cl_uint            num_samples;
    cl_mem             buffer;
} cl_image_desc;

#define CL_SUCCESS 0
#define CL_INVALID_VALUE -30
#define CL_DEVICE_NOT_FOUND -1
#define CL_PLATFORM_NOT_FOUND_KHR -1001

static void* s_cl_handle = nullptr;
static bool s_cl_initialized = false;
static std::mutex s_mutex;
static std::string s_custom_driver_dir;

static bool copy_file_if_needed(const char* src_path, const char* dst_path) {
    struct stat st_src;
    if (stat(src_path, &st_src) != 0) return false;

    struct stat st_dst;
    if (stat(dst_path, &st_dst) == 0 && st_dst.st_size == st_src.st_size) {
        return true; // Already exists and sizes match
    }

    FILE* src = fopen(src_path, "rb");
    if (!src) return false;

    FILE* dst = fopen(dst_path, "wb");
    if (!dst) {
        fclose(src);
        return false;
    }

    char buffer[16384];
    size_t bytes;
    while ((bytes = fread(buffer, 1, sizeof(buffer), src)) > 0) {
        fwrite(buffer, 1, bytes, dst);
    }
    fclose(src);
    fclose(dst);

    chmod(dst_path, 0755);
    return true;
}

extern "C" void set_opencl_driver_path(const char* dir) {
    std::lock_guard<std::mutex> lock(s_mutex);
    if (dir) s_custom_driver_dir = dir;
}

static void* get_vendor_cl() {
    std::lock_guard<std::mutex> lock(s_mutex);
    if (s_cl_initialized) return s_cl_handle;
    s_cl_initialized = true;

    // Potential local app directories where vendor OpenCL may be staged
    std::vector<std::string> candidate_dirs;
    if (!s_custom_driver_dir.empty()) {
        candidate_dirs.push_back(s_custom_driver_dir);
    }
    candidate_dirs.push_back("/data/user/0/dev.seven_cgpalabs.codingsaathi/files/cl");
    candidate_dirs.push_back("/data/data/dev.seven_cgpalabs.codingsaathi/files/cl");

    // Copy Qualcomm vendor libs to local directory if possible
    for (const auto& dir : candidate_dirs) {
        mkdir(dir.c_str(), 0755);
        copy_file_if_needed("/vendor/lib64/libCB.so", (dir + "/libCB.so").c_str());
        copy_file_if_needed("/vendor/lib64/libOpenCL_adreno.so", (dir + "/libOpenCL_adreno.so").c_str());
        copy_file_if_needed("/vendor/lib64/libOpenCL.so", (dir + "/libOpenCL.so").c_str());
        copy_file_if_needed("/system/vendor/lib64/libOpenCL.so", (dir + "/libOpenCL.so").c_str());
    }

    // Try loading dependent Qualcomm libraries first to resolve symbols
    for (const auto& dir : candidate_dirs) {
        dlopen((dir + "/libCB.so").c_str(), RTLD_NOW | RTLD_GLOBAL);
        dlopen((dir + "/libOpenCL_adreno.so").c_str(), RTLD_NOW | RTLD_GLOBAL);
        
        std::string target = dir + "/libOpenCL.so";
        void* handle = dlopen(target.c_str(), RTLD_NOW | RTLD_LOCAL);
        if (handle) {
            __android_log_print(ANDROID_LOG_INFO, LOG_TAG, "Loaded vendor OpenCL from local staged path: %s", target.c_str());
            s_cl_handle = handle;
            return s_cl_handle;
        }
    }

    // Direct system vendor paths
    const char* direct_paths[] = {
        "/vendor/lib64/libOpenCL.so",
        "/vendor/lib64/libOpenCL_adreno.so",
        "/vendor/lib64/libCB.so",
        "/system/vendor/lib64/libOpenCL.so",
        "/system/vendor/lib64/libOpenCL_adreno.so",
        "/system/lib64/libOpenCL.so",
        "/vendor/lib64/egl/libGLES_mali.so",
        "/system/vendor/lib64/egl/libGLES_mali.so",
        nullptr
    };

    for (int i = 0; direct_paths[i] != nullptr; ++i) {
        void* handle = dlopen(direct_paths[i], RTLD_NOW | RTLD_LOCAL);
        if (handle) {
            __android_log_print(ANDROID_LOG_INFO, LOG_TAG, "Loaded vendor OpenCL directly from: %s", direct_paths[i]);
            s_cl_handle = handle;
            return s_cl_handle;
        }
    }

    __android_log_print(ANDROID_LOG_WARN, LOG_TAG, "No vendor OpenCL driver library could be loaded");
    return nullptr;
}

#define GET_FN(name) \
    typedef decltype(&name) name##_fn; \
    static name##_fn s_##name = nullptr; \
    if (!s_##name) { \
        void* h = get_vendor_cl(); \
        if (h) s_##name = reinterpret_cast<name##_fn>(dlsym(h, #name)); \
    }

extern "C" {

cl_int clGetPlatformIDs(cl_uint num_entries, cl_platform_id *platforms, cl_uint *num_platforms) {
    GET_FN(clGetPlatformIDs);
    if (s_clGetPlatformIDs) return s_clGetPlatformIDs(num_entries, platforms, num_platforms);
    if (num_platforms) *num_platforms = 0;
    return CL_PLATFORM_NOT_FOUND_KHR;
}

cl_int clGetPlatformInfo(cl_platform_id platform, cl_platform_info param_name, size_t param_value_size, void *param_value, size_t *param_value_size_ret) {
    GET_FN(clGetPlatformInfo);
    if (s_clGetPlatformInfo) return s_clGetPlatformInfo(platform, param_name, param_value_size, param_value, param_value_size_ret);
    return CL_INVALID_VALUE;
}

cl_int clGetDeviceIDs(cl_platform_id platform, cl_device_type device_type, cl_uint num_entries, cl_device_id *devices, cl_uint *num_devices) {
    GET_FN(clGetDeviceIDs);
    if (s_clGetDeviceIDs) return s_clGetDeviceIDs(platform, device_type, num_entries, devices, num_devices);
    if (num_devices) *num_devices = 0;
    return CL_DEVICE_NOT_FOUND;
}

cl_int clGetDeviceInfo(cl_device_id device, cl_device_info param_name, size_t param_value_size, void *param_value, size_t *param_value_size_ret) {
    GET_FN(clGetDeviceInfo);
    if (s_clGetDeviceInfo) return s_clGetDeviceInfo(device, param_name, param_value_size, param_value, param_value_size_ret);
    return CL_INVALID_VALUE;
}

cl_context clCreateContext(const cl_context_properties *properties, cl_uint num_devices, const cl_device_id *devices, void (*pfn_notify)(const char *, const void *, size_t, void *), void *user_data, cl_int *errcode_ret) {
    GET_FN(clCreateContext);
    if (s_clCreateContext) return s_clCreateContext(properties, num_devices, devices, pfn_notify, user_data, errcode_ret);
    if (errcode_ret) *errcode_ret = CL_INVALID_VALUE;
    return nullptr;
}

cl_command_queue clCreateCommandQueue(cl_context context, cl_device_id device, cl_command_queue_properties properties, cl_int *errcode_ret) {
    GET_FN(clCreateCommandQueue);
    if (s_clCreateCommandQueue) return s_clCreateCommandQueue(context, device, properties, errcode_ret);
    if (errcode_ret) *errcode_ret = CL_INVALID_VALUE;
    return nullptr;
}

cl_command_queue clCreateCommandQueueWithProperties(cl_context context, cl_device_id device, const cl_queue_properties *properties, cl_int *errcode_ret) {
    GET_FN(clCreateCommandQueueWithProperties);
    if (s_clCreateCommandQueueWithProperties) return s_clCreateCommandQueueWithProperties(context, device, properties, errcode_ret);
    if (errcode_ret) *errcode_ret = CL_INVALID_VALUE;
    return nullptr;
}

cl_int clReleaseCommandQueue(cl_command_queue command_queue) {
    GET_FN(clReleaseCommandQueue);
    if (s_clReleaseCommandQueue) return s_clReleaseCommandQueue(command_queue);
    return CL_SUCCESS;
}

cl_int clReleaseContext(cl_context context) {
    GET_FN(clReleaseContext);
    if (s_clReleaseContext) return s_clReleaseContext(context);
    return CL_SUCCESS;
}

cl_int clSetKernelArg(cl_kernel kernel, cl_uint arg_index, size_t arg_size, const void *arg_value) {
    GET_FN(clSetKernelArg);
    if (s_clSetKernelArg) return s_clSetKernelArg(kernel, arg_index, arg_size, arg_value);
    return CL_INVALID_VALUE;
}

cl_int clGetKernelWorkGroupInfo(cl_kernel kernel, cl_device_id device, cl_kernel_work_group_info param_name, size_t param_value_size, void *param_value, size_t *param_value_size_ret) {
    GET_FN(clGetKernelWorkGroupInfo);
    if (s_clGetKernelWorkGroupInfo) return s_clGetKernelWorkGroupInfo(kernel, device, param_name, param_value_size, param_value, param_value_size_ret);
    return CL_INVALID_VALUE;
}

cl_int clEnqueueNDRangeKernel(cl_command_queue command_queue, cl_kernel kernel, cl_uint work_dim, const size_t *global_work_offset, const size_t *global_work_size, const size_t *local_work_size, cl_uint num_events_in_wait_list, const cl_event *event_wait_list, cl_event *event) {
    GET_FN(clEnqueueNDRangeKernel);
    if (s_clEnqueueNDRangeKernel) return s_clEnqueueNDRangeKernel(command_queue, kernel, work_dim, global_work_offset, global_work_size, local_work_size, num_events_in_wait_list, event_wait_list, event);
    return CL_INVALID_VALUE;
}

cl_mem clCreateBuffer(cl_context context, cl_mem_flags flags, size_t size, void *host_ptr, cl_int *errcode_ret) {
    GET_FN(clCreateBuffer);
    if (s_clCreateBuffer) return s_clCreateBuffer(context, flags, size, host_ptr, errcode_ret);
    if (errcode_ret) *errcode_ret = CL_INVALID_VALUE;
    return nullptr;
}

cl_int clReleaseMemObject(cl_mem memobj) {
    GET_FN(clReleaseMemObject);
    if (s_clReleaseMemObject) return s_clReleaseMemObject(memobj);
    return CL_SUCCESS;
}

cl_mem clCreateImage(cl_context context, cl_mem_flags flags, const cl_image_format *image_format, const cl_image_desc *image_desc, void *host_ptr, cl_int *errcode_ret) {
    GET_FN(clCreateImage);
    if (s_clCreateImage) return s_clCreateImage(context, flags, image_format, image_desc, host_ptr, errcode_ret);
    if (errcode_ret) *errcode_ret = CL_INVALID_VALUE;
    return nullptr;
}

cl_mem clCreateSubBuffer(cl_mem buffer, cl_mem_flags flags, cl_buffer_create_type buffer_create_type, const void *buffer_create_info, cl_int *errcode_ret) {
    GET_FN(clCreateSubBuffer);
    if (s_clCreateSubBuffer) return s_clCreateSubBuffer(buffer, flags, buffer_create_type, buffer_create_info, errcode_ret);
    if (errcode_ret) *errcode_ret = CL_INVALID_VALUE;
    return nullptr;
}

cl_int clFinish(cl_command_queue command_queue) {
    GET_FN(clFinish);
    if (s_clFinish) return s_clFinish(command_queue);
    return CL_SUCCESS;
}

cl_int clEnqueueBarrierWithWaitList(cl_command_queue command_queue, cl_uint num_events_in_wait_list, const cl_event *event_wait_list, cl_event *event) {
    GET_FN(clEnqueueBarrierWithWaitList);
    if (s_clEnqueueBarrierWithWaitList) return s_clEnqueueBarrierWithWaitList(command_queue, num_events_in_wait_list, event_wait_list, event);
    return CL_SUCCESS;
}

cl_int clWaitForEvents(cl_uint num_events, const cl_event *event_list) {
    GET_FN(clWaitForEvents);
    if (s_clWaitForEvents) return s_clWaitForEvents(num_events, event_list);
    return CL_SUCCESS;
}

cl_int clReleaseEvent(cl_event event) {
    GET_FN(clReleaseEvent);
    if (s_clReleaseEvent) return s_clReleaseEvent(event);
    return CL_SUCCESS;
}

cl_int clEnqueueCopyBuffer(cl_command_queue command_queue, cl_mem src_buffer, cl_mem dst_buffer, size_t src_offset, size_t dst_offset, size_t size, cl_uint num_events_in_wait_list, const cl_event *event_wait_list, cl_event *event) {
    GET_FN(clEnqueueCopyBuffer);
    if (s_clEnqueueCopyBuffer) return s_clEnqueueCopyBuffer(command_queue, src_buffer, dst_buffer, src_offset, dst_offset, size, num_events_in_wait_list, event_wait_list, event);
    return CL_INVALID_VALUE;
}

cl_int clEnqueueMarkerWithWaitList(cl_command_queue command_queue, cl_uint num_events_in_wait_list, const cl_event *event_wait_list, cl_event *event) {
    GET_FN(clEnqueueMarkerWithWaitList);
    if (s_clEnqueueMarkerWithWaitList) return s_clEnqueueMarkerWithWaitList(command_queue, num_events_in_wait_list, event_wait_list, event);
    return CL_SUCCESS;
}

cl_int clFlush(cl_command_queue command_queue) {
    GET_FN(clFlush);
    if (s_clFlush) return s_clFlush(command_queue);
    return CL_SUCCESS;
}

cl_kernel clCreateKernel(cl_program program, const char *kernel_name, cl_int *errcode_ret) {
    GET_FN(clCreateKernel);
    if (s_clCreateKernel) return s_clCreateKernel(program, kernel_name, errcode_ret);
    if (errcode_ret) *errcode_ret = CL_INVALID_VALUE;
    return nullptr;
}

cl_mem clCreateBufferWithProperties(cl_context context, const cl_mem_properties *properties, cl_mem_flags flags, size_t size, void *host_ptr, cl_int *errcode_ret) {
    GET_FN(clCreateBufferWithProperties);
    if (s_clCreateBufferWithProperties) return s_clCreateBufferWithProperties(context, properties, flags, size, host_ptr, errcode_ret);
    return clCreateBuffer(context, flags, size, host_ptr, errcode_ret);
}

cl_int clReleaseProgram(cl_program program) {
    GET_FN(clReleaseProgram);
    if (s_clReleaseProgram) return s_clReleaseProgram(program);
    return CL_SUCCESS;
}

cl_program clCreateProgramWithSource(cl_context context, cl_uint count, const char **strings, const size_t *lengths, cl_int *errcode_ret) {
    GET_FN(clCreateProgramWithSource);
    if (s_clCreateProgramWithSource) return s_clCreateProgramWithSource(context, count, strings, lengths, errcode_ret);
    if (errcode_ret) *errcode_ret = CL_INVALID_VALUE;
    return nullptr;
}

cl_int clBuildProgram(cl_program program, cl_uint num_devices, const cl_device_id *device_list, const char *options, void (*pfn_notify)(cl_program, void *), void *user_data) {
    GET_FN(clBuildProgram);
    if (s_clBuildProgram) return s_clBuildProgram(program, num_devices, device_list, options, pfn_notify, user_data);
    return CL_INVALID_VALUE;
}

cl_int clGetProgramBuildInfo(cl_program program, cl_device_id device, cl_program_build_info param_name, size_t param_value_size, void *param_value, size_t *param_value_size_ret) {
    GET_FN(clGetProgramBuildInfo);
    if (s_clGetProgramBuildInfo) return s_clGetProgramBuildInfo(program, device, param_name, param_value_size, param_value, param_value_size_ret);
    return CL_INVALID_VALUE;
}

cl_int clEnqueueWriteBuffer(cl_command_queue command_queue, cl_mem buffer, cl_bool blocking_write, size_t offset, size_t size, const void *ptr, cl_uint num_events_in_wait_list, const cl_event *event_wait_list, cl_event *event) {
    GET_FN(clEnqueueWriteBuffer);
    if (s_clEnqueueWriteBuffer) return s_clEnqueueWriteBuffer(command_queue, buffer, blocking_write, offset, size, ptr, num_events_in_wait_list, event_wait_list, event);
    return CL_INVALID_VALUE;
}

cl_int clEnqueueReadBuffer(cl_command_queue command_queue, cl_mem buffer, cl_bool blocking_read, size_t offset, size_t size, void *ptr, cl_uint num_events_in_wait_list, const cl_event *event_wait_list, cl_event *event) {
    GET_FN(clEnqueueReadBuffer);
    if (s_clEnqueueReadBuffer) return s_clEnqueueReadBuffer(command_queue, buffer, blocking_read, offset, size, ptr, num_events_in_wait_list, event_wait_list, event);
    return CL_INVALID_VALUE;
}

cl_int clEnqueueFillBuffer(cl_command_queue command_queue, cl_mem buffer, const void *pattern, size_t pattern_size, size_t offset, size_t size, cl_uint num_events_in_wait_list, const cl_event *event_wait_list, cl_event *event) {
    GET_FN(clEnqueueFillBuffer);
    if (s_clEnqueueFillBuffer) return s_clEnqueueFillBuffer(command_queue, buffer, pattern, pattern_size, offset, size, num_events_in_wait_list, event_wait_list, event);
    return CL_INVALID_VALUE;
}

cl_int clReleaseKernel(cl_kernel kernel) {
    GET_FN(clReleaseKernel);
    if (s_clReleaseKernel) return s_clReleaseKernel(kernel);
    return CL_SUCCESS;
}

cl_program clCreateProgramWithBinary(cl_context context, cl_uint num_devices, const cl_device_id *device_list, const size_t *lengths, const unsigned char **binaries, cl_int *binary_status, cl_int *errcode_ret) {
    GET_FN(clCreateProgramWithBinary);
    if (s_clCreateProgramWithBinary) return s_clCreateProgramWithBinary(context, num_devices, device_list, lengths, binaries, binary_status, errcode_ret);
    if (errcode_ret) *errcode_ret = CL_INVALID_VALUE;
    return nullptr;
}

cl_int clGetProgramInfo(cl_program program, cl_program_info param_name, size_t param_value_size, void *param_value, size_t *param_value_size_ret) {
    GET_FN(clGetProgramInfo);
    if (s_clGetProgramInfo) return s_clGetProgramInfo(program, param_name, param_value_size, param_value, param_value_size_ret);
    return CL_INVALID_VALUE;
}

void* clEnqueueMapBuffer(cl_command_queue command_queue, cl_mem buffer, cl_bool blocking_map, cl_map_flags map_flags, size_t offset, size_t size, cl_uint num_events_in_wait_list, const cl_event *event_wait_list, cl_event *event, cl_int *errcode_ret) {
    GET_FN(clEnqueueMapBuffer);
    if (s_clEnqueueMapBuffer) return s_clEnqueueMapBuffer(command_queue, buffer, blocking_map, map_flags, offset, size, num_events_in_wait_list, event_wait_list, event, errcode_ret);
    if (errcode_ret) *errcode_ret = CL_INVALID_VALUE;
    return nullptr;
}

cl_int clEnqueueUnmapMemObject(cl_command_queue command_queue, cl_mem memobj, void *mapped_ptr, cl_uint num_events_in_wait_list, const cl_event *event_wait_list, cl_event *event) {
    GET_FN(clEnqueueUnmapMemObject);
    if (s_clEnqueueUnmapMemObject) return s_clEnqueueUnmapMemObject(command_queue, memobj, mapped_ptr, num_events_in_wait_list, event_wait_list, event);
    return CL_SUCCESS;
}

cl_int clGetEventProfilingInfo(cl_event event, cl_profiling_info param_name, size_t param_value_size, void *param_value, size_t *param_value_size_ret) {
    GET_FN(clGetEventProfilingInfo);
    if (s_clGetEventProfilingInfo) return s_clGetEventProfilingInfo(event, param_name, param_value_size, param_value, param_value_size_ret);
    return CL_INVALID_VALUE;
}

cl_int clRetainCommandQueue(cl_command_queue command_queue) {
    GET_FN(clRetainCommandQueue);
    if (s_clRetainCommandQueue) return s_clRetainCommandQueue(command_queue);
    return CL_SUCCESS;
}

cl_int clRetainContext(cl_context context) {
    GET_FN(clRetainContext);
    if (s_clRetainContext) return s_clRetainContext(context);
    return CL_SUCCESS;
}

cl_int clRetainMemObject(cl_mem memobj) {
    GET_FN(clRetainMemObject);
    if (s_clRetainMemObject) return s_clRetainMemObject(memobj);
    return CL_SUCCESS;
}

cl_int clRetainProgram(cl_program program) {
    GET_FN(clRetainProgram);
    if (s_clRetainProgram) return s_clRetainProgram(program);
    return CL_SUCCESS;
}

cl_int clRetainKernel(cl_kernel kernel) {
    GET_FN(clRetainKernel);
    if (s_clRetainKernel) return s_clRetainKernel(kernel);
    return CL_SUCCESS;
}

cl_int clRetainEvent(cl_event event) {
    GET_FN(clRetainEvent);
    if (s_clRetainEvent) return s_clRetainEvent(event);
    return CL_SUCCESS;
}

}
