use rayon::prelude::*;
use std::hint::black_box;
use std::time::Instant;

#[derive(Clone, Copy)]
struct Node {
    value: i64,
    left: i64,
    right: i64,
}

fn serial_sum_tree(nodes: &[Node], index: usize) -> i64 {
    let mut result = nodes[index].value;
    if nodes[index].left >= 0 {
        result += serial_sum_tree(nodes, nodes[index].left as usize);
    }
    if nodes[index].right >= 0 {
        result += serial_sum_tree(nodes, nodes[index].right as usize);
    }
    result
}

fn parallel_sum_tree(pool: &rayon::ThreadPool, nodes: &[Node], index: usize) -> i64 {
    let left = nodes[index].left;
    let right = nodes[index].right;
    if left >= 0 && right >= 0 {
        let (a, b) = pool.join(
            || parallel_sum_tree(pool, nodes, left as usize),
            || parallel_sum_tree(pool, nodes, right as usize),
        );
        nodes[index].value + a + b
    } else if left >= 0 {
        nodes[index].value + parallel_sum_tree(pool, nodes, left as usize)
    } else if right >= 0 {
        nodes[index].value + parallel_sum_tree(pool, nodes, right as usize)
    } else {
        nodes[index].value
    }
}

fn work(index: u64) -> u64 {
    let mut x = index.wrapping_add(0x9e3779b97f4a7c15);
    for _ in 0..64 {
        x = x.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        x ^= x >> 17;
    }
    x
}

fn serial_flat(data: &[u64]) -> u64 {
    data.iter().fold(0u64, |acc, &v| acc.wrapping_add(v))
}

fn serial_compute(count: usize) -> u64 {
    let mut total = 0u64;
    for i in 0..count {
        total = total.wrapping_add(work(i as u64));
    }
    total
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("usage: {} <tree|flat|compute> <count> [lanes]", args[0]);
        std::process::exit(2);
    }
    let workload = &args[1];
    let count: usize = args[2].parse().unwrap();
    let lanes: usize = if args.len() > 3 { args[3].parse().unwrap() } else { 32 };

    let pool = rayon::ThreadPoolBuilder::new()
        .num_threads(if lanes == 0 { 1 } else { lanes })
        .build()
        .unwrap();

    match workload.as_str() {
        "tree" => {
            let nodes: Vec<Node> = (0..count)
                .map(|i| Node {
                    value: 1,
                    left: if 2 * i + 1 < count { (2 * i + 1) as i64 } else { -1 },
                    right: if 2 * i + 2 < count { (2 * i + 2) as i64 } else { -1 },
                })
                .collect();
            let mut serial_result = 0i64;
            let mut parallel_result = 0i64;
            let mut serial_best = u128::MAX;
            let mut parallel_best = u128::MAX;
            for _ in 0..9 {
                let start = Instant::now();
                serial_result = serial_sum_tree(&nodes, 0);
                let t = start.elapsed().as_nanos();
                if t < serial_best { serial_best = t; }

                let start = Instant::now();
                parallel_result = pool.install(|| parallel_sum_tree(&pool, &nodes, 0));
                let t = start.elapsed().as_nanos();
                if t < parallel_best { parallel_best = t; }
            }
            black_box((serial_result, parallel_result));
            if serial_result != parallel_result {
                eprintln!("mismatch serial={} parallel={}", serial_result, parallel_result);
                std::process::exit(1);
            }
            println!(
                "rayon tree n={} lanes={} serial_ns={} parallel_ns={} speedup={:.2}",
                count, lanes, serial_best, parallel_best,
                serial_best as f64 / parallel_best as f64
            );
        }
        "flat" => {
            let data: Vec<u64> = (0..count as u64).collect();
            let mut serial_result = 0u64;
            let mut parallel_result = 0u64;
            let mut serial_best = u128::MAX;
            let mut parallel_best = u128::MAX;
            for _ in 0..7 {
                let start = Instant::now();
                serial_result = serial_flat(&data);
                let t = start.elapsed().as_nanos();
                if t < serial_best { serial_best = t; }

                let start = Instant::now();
                parallel_result = pool.install(|| data.par_iter().copied().reduce(|| 0u64, |a, b| a.wrapping_add(b)));
                let t = start.elapsed().as_nanos();
                if t < parallel_best { parallel_best = t; }
            }
            black_box((serial_result, parallel_result));
            if serial_result != parallel_result {
                eprintln!("mismatch serial={} parallel={}", serial_result, parallel_result);
                std::process::exit(1);
            }
            println!(
                "rayon flat n={} lanes={} serial_ns={} parallel_ns={} speedup={:.2}",
                count, lanes, serial_best, parallel_best,
                serial_best as f64 / parallel_best as f64
            );
        }
        "compute" => {
            let mut serial_result = 0u64;
            let mut parallel_result = 0u64;
            let mut serial_best = u128::MAX;
            let mut parallel_best = u128::MAX;
            for _ in 0..7 {
                let start = Instant::now();
                serial_result = serial_compute(count);
                let t = start.elapsed().as_nanos();
                if t < serial_best { serial_best = t; }

                let start = Instant::now();
                parallel_result = pool.install(|| {
                    (0..count)
                        .into_par_iter()
                        .map(|i| work(i as u64))
                        .reduce(|| 0u64, |a, b| a.wrapping_add(b))
                });
                let t = start.elapsed().as_nanos();
                if t < parallel_best { parallel_best = t; }
            }
            black_box((serial_result, parallel_result));
            if serial_result != parallel_result {
                eprintln!("mismatch serial={} parallel={}", serial_result, parallel_result);
                std::process::exit(1);
            }
            println!(
                "rayon compute n={} lanes={} serial_ns={} parallel_ns={} speedup={:.2}",
                count, lanes, serial_best, parallel_best,
                serial_best as f64 / parallel_best as f64
            );
        }
        other => {
            eprintln!("unknown workload: {}", other);
            std::process::exit(2);
        }
    }
}
