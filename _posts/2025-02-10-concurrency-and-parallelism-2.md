---
title:  "Concurrency and Parallelism in Java - Part 2"
categories:
  - Java
  - Concurrency
  - Parallelism
tags:
  - Blog
toc: true
last_modified_at: 2025-02-10T08:05:34-05:00
---

# Concurrency and Parallelism in Java (Part 2)

In a [previous post](http://www.simplex-software.fr/posts-archive/concurrency-and-parallelism/), we've been looking at a couple of interesting
aspects concerning the concurrency and parallelism in Java. We've seen that, with
parallel processing, the maximum number of parallel tasks that can be executed
at any given moment,
i.e. the maximum number of the simultaneously running platforms threads,
is equal to the number of the available CPU cores. If the number of the currently
active threads is superior to the one of the available CPU cores, then the number
of threads waiting for resources will be equal to the difference between the total
number of the active threads and the number of the available CPU cores.

In conclusion, more the difference between the number of the currently active
threads and the one of the available CPU cores is important, more important will
be the number of the blocked threads, waiting for the CPU. But would this impact
the application's overall performances and, if yes, how ?

One of the most common ways to address parallel processing in Java is through
the [work stealing](https://en.wikipedia.org/wiki/Work_stealing) design pattern
implemented by the `ForkJoinPool`. Java provides two categoris of `ForkJoinPool`:

  - a common `ForkJoinPool` JVM wide, shared across applications, used by default by parallel streams;
  - customized `ForkJoinPool` created explicitly for specific use cases and supposed to provide more control over the resources usage.

The Java common `ForkJoinPool` parallelism level defaults to a number of threads equal to the
number of the available CPU cores minus 1. It is configurable and can be set via the system property
`java.util.concurrent.ForkJoinPool.common.parallelism`. For example:

    System.setProperty("java.util.concurrent.ForkJoinPool.common.parallelism", "16");

sets the Java common `ForkJoinPool` maximum number of parallel threads to 16.

As for the customized `ForkJoinPool`, their parallelism level is initialized at
their instantiation time, via an input argument. This input argument is optional
and, if missing, the same value as the one defining currently the common
`ForkJoinPool` parallelism will be used.

Now, an interesting question would be to know what's the relationship between
this parallelism level and the one of the platform's available CPU cores ? The
typical recommendation
would be to set the parallelism level to the number of cores, or slightly higher.
For example, for CPU-intensive tasks, set the parallelism level to the number
of cores, while for I/O intensive tasks, set it according to the formula below:

    parallelism = number of cores * waiting time / service time

Here `waiting time` is the time spent waiting for I/O operations (like network
calls, disk operations, etc.) and `service time ` is the actual CPU processing
time. For example, let's say that our task makes a database query which takes
100 ms, after which it processes the results during 20 ms. Then:

    paralallism = 8 * (1 + 100/20) = 48

The reasoning behind this formula is:

  - During I/O operations, CPU cores are idle.
  - While one thread is waiting for I/O, other threads can use the CPU.
  - The ratio (waiting time / service time) helps determine how many additional threads can effectively use the CPU during I/O waits.
  - A higher waiting-to-service time ratio justifies more threads since cores would otherwise be idle during I/O waits.

Let's look at an implementation trying to simulate such a computing model (the code is available in the [GitHub repository](https://github.com/nicolasduminil/concurrency-and-parallelism-in-java.git)):

    public class TestForkJoinPool
    {
      private static final Logger LOG = Logger.getLogger(TestForkJoinPool.class.getName());
      private static final int CORES = Runtime.getRuntime().availableProcessors();
      private static final double WAITING_TIME = 100;
      private static final double SERVICE_TIME = 20;
      private static final int OPTIMAL_PARALLELISM = (int) (CORES * (1 + WAITING_TIME / SERVICE_TIME));

      @Test
      public void testForkJoinPool() throws Exception
      {
        LOG.info(">>> Setting parallelism to %s for %d available CPU cores (waiting/service ratio: %.1f)"
         .formatted(OPTIMAL_PARALLELISM, CORES, WAITING_TIME / SERVICE_TIME));
        Instant start = Instant.now();
        try (var pool = new ForkJoinPool(OPTIMAL_PARALLELISM))
        {
          pool.submit(() -> run()).get();
        }
        Duration duration = Duration.between(start, Instant.now());
        LOG.info("Threads: %d, Duration: %d ms"
          .formatted(OPTIMAL_PARALLELISM, duration.toMillis()));
      }

      private static void run()
      {
        long count = Stream.generate(() ->
        {
          try
          {
            TimeUnit.MILLISECONDS.sleep(100);
            simulateCpuWork(20);
            return 1;
          }
          catch (InterruptedException e)
          {
            throw new RuntimeException(e);
          }
        })
        .parallel()
        .limit(10)
        .count();
      }

      private static void simulateCpuWork(long milliseconds)
      {
        long startTime = System.nanoTime();
        double result = 0;
        while (System.nanoTime() - startTime < milliseconds * 1_000_000)
          result += Math.sin(result) + Math.cos(result);
      }
    }

> **_NOTE:_**  In this example we've used a custom `ForkJoinPool` but the test
> result would have been the same for the common `ForkJoinPool`.

In the code above we're simulating 10 operations consisting each in a I/O
intensive processing, taking 100 ms, and a CPU intensive one, taking 20 ms,
so a total duration 1 200 ms.

Running this test on my laptop having 8 available CPU cores, I get this:

    Feb 10, 2025 2:40:48 PM fr.simplex_software.workshop.tests.TestForkJoinPool testForkJoinPool
    INFO: >>> Setting parallelism to 48 for 8 available CPU cores (waiting/service ratio: 5.0)
    Feb 10, 2025 2:40:48 PM fr.simplex_software.workshop.tests.TestForkJoinPool testForkJoinPool
    INFO: Threads: 48, Duration: 255 ms

As you can see, it takes 255 ms to perform the 10 operations which total duration
is of 1 200 ms. In order to check
the validity of the mentioned formula, I instantiated the common `ForkJoinPool` with a non-optimal
thread numbers, for example:

    ...
    try (var pool = new ForkJoinPool(1))
    ...

This time the total duration was of 1 445 ms, i.e. more than 5 times slower.
Meaning that the optimal setting completes the work much faster. But what happens
if I set the parallelism level at a number of thread higher than the optimal one ?
For example, doing:

    ...
    try (var pool = new ForkJoinPool(64))
    ...

I was expecting to see degraded performances but, surprisingly, the test performs
almost as fast as when using the optimal value, or, in the worst case, just a little
bit slower.

In order to illustrate this let's modify the test as follows:

    @Test
    public void compareThreadCounts() throws Exception
    {
      int[] threadCounts = {
        1,
        CORES,
        OPTIMAL_PARALLELISM,
        OPTIMAL_PARALLELISM * 2,
        OPTIMAL_PARALLELISM * 4
      };

      for (int threadCount : threadCounts)
      {
        LOG.info(">>> Have set parallelism to %s for %d available CPU cores (waiting/service ratio: %.1f)"
          .formatted(threadCount, CORES, WAITING_TIME / SERVICE_TIME));
        Instant start = Instant.now();
        try (var pool = new ForkJoinPool(threadCount))
        {
          pool.submit(() -> run()).get();
        }
        Duration duration = Duration.between(start, Instant.now());
        LOG.info("Threads: %d, Duration: %d ms"
          .formatted(threadCount, duration.toMillis()));
      }
    }
    ...

Running this test on my machine I'm getting the following results:

| Nb. of threads | Duration |
|----------------|----------|
| 1              | 1443 ms  |
| 8              | 361 ms   |
| 48             | 253 ms   |
| 96             | 264 ms   |
| 192            | 279 ms   |

As you can see, the best result is obtained for the optimal parallelism level.
When setting it at inferior values the test is significantly slower but when
setting it at higher values, the test is just a bit slower.

In conclusion, this formula works but, before using it, you need to take into
account the fact that it isn't a panacea. It's based on idealized assumptions
about workload distribution
and real-world performance can vary due to many factors.

Accordingly, the following best practices have to be observed when applying it:

  1. Use the formula as a starting point, not a fixed rule.
  2. Benchmark with your specific workload.
  3. Monitor system resources (CPU, memory, etc.).
  4. Consider implementing adaptive thread pool sizing.
  5. Watch for signs of thread contention.

The optimal parallelism level is more of a minimum threshold for good performance
rather than a strict maximum. As long as you're not seeing degraded performance
or resource exhaustion, having more threads than the calculated optimal can be
perfectly fine.

If you're interested in these topics then you might like [![50 Shades of Java Executors](/assets/images/executors.jpg)](https://shorturl.at/ohTjM)

