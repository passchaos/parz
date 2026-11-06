#include <omp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    int64_t value;
    int64_t left;
    int64_t right;
} Node;

static int64_t serial_sum(const Node *nodes, size_t index) {
    int64_t result = nodes[index].value;
    if (nodes[index].left >= 0) result += serial_sum(nodes, (size_t)nodes[index].left);
    if (nodes[index].right >= 0) result += serial_sum(nodes, (size_t)nodes[index].right);
    return result;
}

#define TREE_CUTOFF_DEPTH 8

static int64_t parallel_sum(const Node *nodes, size_t index, int depth) {
    int64_t result = nodes[index].value;
    int64_t l = nodes[index].left;
    int64_t r = nodes[index].right;
    if (l >= 0 && r >= 0) {
        if (depth >= TREE_CUTOFF_DEPTH) {
            return result + serial_sum(nodes, (size_t)l) + serial_sum(nodes, (size_t)r);
        }
        int64_t a;
        int64_t b;
#pragma omp task shared(a) firstprivate(nodes, l, depth)
        a = parallel_sum(nodes, (size_t)l, depth + 1);
#pragma omp task shared(b) firstprivate(nodes, r, depth)
        b = parallel_sum(nodes, (size_t)r, depth + 1);
#pragma omp taskwait
        return result + a + b;
    }
    if (l >= 0) result += serial_sum(nodes, (size_t)l);
    if (r >= 0) result += serial_sum(nodes, (size_t)r);
    return result;
}

static int64_t serial_sum_flat(const int64_t *values, size_t n, size_t index) {
    int64_t result = values[index];
    size_t left = 2 * index + 1;
    size_t right = 2 * index + 2;
    if (left < n) result += serial_sum_flat(values, n, left);
    if (right < n) result += serial_sum_flat(values, n, right);
    return result;
}

static int64_t parallel_sum_flat(const int64_t *values, size_t n, size_t index, int depth) {
    if (depth >= TREE_CUTOFF_DEPTH) return serial_sum_flat(values, n, index);
    int64_t result = values[index];
    size_t left = 2 * index + 1;
    size_t right = 2 * index + 2;
    if (right < n) {
        int64_t a;
        int64_t b;
#pragma omp task shared(a) firstprivate(values, n, left, depth)
        a = parallel_sum_flat(values, n, left, depth + 1);
#pragma omp task shared(b) firstprivate(values, n, right, depth)
        b = parallel_sum_flat(values, n, right, depth + 1);
#pragma omp taskwait
        return result + a + b;
    }
    if (left < n) result += serial_sum_flat(values, n, left);
    return result;
}

static inline uint64_t work(uint64_t index) {
    uint64_t x = index + 0x9e3779b97f4a7c15ULL;
    for (uint32_t round = 0; round < 64; round++) {
        x = x * 6364136223846793005ULL + 1442695040888963407ULL;
        x ^= x >> 17;
    }
    return x;
}

static uint64_t serial_flat(const uint64_t *data, size_t count) {
    uint64_t total = 0;
    for (size_t i = 0; i < count; i++) total += data[i];
    return total;
}

static uint64_t serial_compute(size_t count) {
    uint64_t total = 0;
    for (size_t i = 0; i < count; i++) total += work((uint64_t)i);
    return total;
}

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <tree|flat|compute> <count> [lanes]\n", argv[0]);
        return 2;
    }
    const char *workload = argv[1];
    size_t count = strtoull(argv[2], NULL, 10);
    int lanes = argc > 3 ? atoi(argv[3]) : 32;
    omp_set_num_threads(lanes == 0 ? 1 : lanes);

    if (strcmp(workload, "tree-flat") == 0) {
        int64_t *values = malloc(count * sizeof(int64_t));
        if (!values) return 2;
        for (size_t i = 0; i < count; i++) values[i] = 1;
        int64_t serial_result = 0;
        int64_t parallel_result = 0;
        uint64_t serial_best = UINT64_MAX;
        uint64_t parallel_best = UINT64_MAX;
        for (int rep = 0; rep < 9; rep++) {
            uint64_t start = now_ns();
            serial_result = serial_sum_flat(values, count, 0);
            uint64_t t = now_ns() - start;
            if (t < serial_best) serial_best = t;

            start = now_ns();
#pragma omp parallel
            {
#pragma omp single
                parallel_result = parallel_sum_flat(values, count, 0, 0);
            }
            t = now_ns() - start;
            if (t < parallel_best) parallel_best = t;
        }
        if (serial_result != parallel_result) {
            fprintf(stderr, "mismatch serial=%lld parallel=%lld\n",
                    (long long)serial_result, (long long)parallel_result);
            free(values);
            return 1;
        }
        printf("openmp tree-flat n=%zu lanes=%d serial_ns=%llu parallel_ns=%llu speedup=%.2f\n",
               count, lanes, (unsigned long long)serial_best, (unsigned long long)parallel_best,
               (double)serial_best / (double)parallel_best);
        free(values);
        return 0;
    }

    if (strcmp(workload, "tree") == 0) {
        Node *nodes = malloc(count * sizeof(Node));
        if (!nodes) return 2;
        for (size_t i = 0; i < count; i++) {
            nodes[i].value = 1;
            nodes[i].left = (2 * i + 1 < count) ? (int64_t)(2 * i + 1) : -1;
            nodes[i].right = (2 * i + 2 < count) ? (int64_t)(2 * i + 2) : -1;
        }
        int64_t serial_result = 0;
        int64_t parallel_result = 0;
        uint64_t serial_best = UINT64_MAX;
        uint64_t parallel_best = UINT64_MAX;
        for (int rep = 0; rep < 9; rep++) {
            uint64_t start = now_ns();
            serial_result = serial_sum(nodes, 0);
            uint64_t t = now_ns() - start;
            if (t < serial_best) serial_best = t;

            start = now_ns();
#pragma omp parallel
            {
#pragma omp single
                parallel_result = parallel_sum(nodes, 0, 0);
            }
            t = now_ns() - start;
            if (t < parallel_best) parallel_best = t;
        }
        if (serial_result != parallel_result) {
            fprintf(stderr, "mismatch serial=%lld parallel=%lld\n",
                    (long long)serial_result, (long long)parallel_result);
            free(nodes);
            return 1;
        }
        printf("openmp tree n=%zu lanes=%d serial_ns=%llu parallel_ns=%llu speedup=%.2f\n",
               count, lanes, (unsigned long long)serial_best, (unsigned long long)parallel_best,
               (double)serial_best / (double)parallel_best);
        free(nodes);
        return 0;
    }

    if (strcmp(workload, "flat") == 0) {
        uint64_t *data = malloc(count * sizeof(uint64_t));
        if (!data) return 2;
        for (size_t i = 0; i < count; i++) data[i] = i;
        uint64_t serial_result = 0;
        uint64_t parallel_result = 0;
        uint64_t serial_best = UINT64_MAX;
        uint64_t parallel_best = UINT64_MAX;
        for (int rep = 0; rep < 7; rep++) {
            uint64_t start = now_ns();
            serial_result = serial_flat(data, count);
            uint64_t t = now_ns() - start;
            if (t < serial_best) serial_best = t;

            parallel_result = 0;
            start = now_ns();
#pragma omp parallel for reduction(+:parallel_result) schedule(static)
            for (size_t i = 0; i < count; i++) parallel_result += data[i];
            t = now_ns() - start;
            if (t < parallel_best) parallel_best = t;
        }
        if (serial_result != parallel_result) {
            fprintf(stderr, "mismatch serial=%llu parallel=%llu\n",
                    (unsigned long long)serial_result, (unsigned long long)parallel_result);
            free(data);
            return 1;
        }
        printf("openmp flat n=%zu lanes=%d serial_ns=%llu parallel_ns=%llu speedup=%.2f\n",
               count, lanes, (unsigned long long)serial_best, (unsigned long long)parallel_best,
               (double)serial_best / (double)parallel_best);
        free(data);
        return 0;
    }

    if (strcmp(workload, "compute") == 0) {
        uint64_t serial_result = 0;
        uint64_t parallel_result = 0;
        uint64_t serial_best = UINT64_MAX;
        uint64_t parallel_best = UINT64_MAX;
        for (int rep = 0; rep < 7; rep++) {
            uint64_t start = now_ns();
            serial_result = serial_compute(count);
            uint64_t t = now_ns() - start;
            if (t < serial_best) serial_best = t;

            parallel_result = 0;
            start = now_ns();
#pragma omp parallel for reduction(+:parallel_result) schedule(static)
            for (size_t i = 0; i < count; i++) parallel_result += work((uint64_t)i);
            t = now_ns() - start;
            if (t < parallel_best) parallel_best = t;
        }
        if (serial_result != parallel_result) {
            fprintf(stderr, "mismatch serial=%llu parallel=%llu\n",
                    (unsigned long long)serial_result, (unsigned long long)parallel_result);
            return 1;
        }
        printf("openmp compute n=%zu lanes=%d serial_ns=%llu parallel_ns=%llu speedup=%.2f\n",
               count, lanes, (unsigned long long)serial_best, (unsigned long long)parallel_best,
               (double)serial_best / (double)parallel_best);
        return 0;
    }

    fprintf(stderr, "unknown workload: %s\n", workload);
    return 2;
}
