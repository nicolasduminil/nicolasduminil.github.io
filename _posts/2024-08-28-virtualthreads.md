---
title:  "Java Virtual Threads (JEP 444): Serious ?"
categories:
  - Java
  - Virtual threads
  - JEP 444
tags:
  - LinkedIn
toc: true
last_modified_at: 2024-08-28T08:05:34-05:00
---

Now that Java 21 has become your lingua franca and that, since several months, 
you have up your sleeve a complete and certified JEP 444 implementation, you're
probably throwing yourself into playing, running, romping and indulging with the
fun of the virtual threads. Then, it's time for you to read this paper.

In his excellent article, Clement Escoffier tells us the story of his 2 years 
of practice, at Red Hat, with the virtual threads integration in Quarkus and the
lessons that himself and the whole Quarkus team has learned, while exploring this
new feature and trying to find original solutions, aligned with the requirements
of the distributed applications, including but not limited to microservices and
event-driven ones.

Hence, I won't feed you up here with a new TLDR on virtual threads, not only 
because I'm not sure to have understood all their subtleties, but also because 
the net is scattered with a large number of such resources.

So, what did I understand after having read different papers on virtual threads
and after having played for a while with a couple of test cases ? Well, if I'm 
not very sure to have completely understood how they work, I'm instead sure to 
have understood how they don't work. And to those who still believe that this 
spectral solution allows to forget all the asynchronicity complexities and to 
simply execute blocking code without taking care of continuations and other callbacks,
'cause Loom would magically handle everything behind the scene, I'm saying: no,
no, no !

As we know today, there are at least 5 major cases where using virtual threads is
worse than useless: pinning, monopolization, carrier threads collision, pooling
and thread unsafeness. Hopefully, there are more than 5 cases when using virtual
threads is beneficial, but nothing is less certain :-).

As counterintuitive as it might be, using virtual threads for long-running 
processes is inappropriate. This is because long-running processes don't mandatory
foster switching threads but rather tries keeping with the current CPU bound task 
until it finishes. And this is additionally exacerbated by the fact that Loom 
scheduler doesn't support (yet) the thread preemption.

The pinning case is especially typical given its high frequency and, if it might
seem reasonable to deploy the required efforts such that to avoid it happen in 
your own code, how are you supposed to deal with the dozens of libraries, 
utilities, external dependencies, etc., that you're using on daily basis ? Should
you start by patching them such that to fix the pinning cases, as they had to do
at Red Hat with very well-known artifacts like Postgres JDBC driver and even 
Hibernate ? Whatevs, this doesn't seem too serious, does it ?

Last but not least, the most appropriate use cases to adopt Loom based solutions
are the ones requiring a high level of thread switches, where a single carrier 
thread is executing potentially millions of virtual ones. And since there are 
certainly lots of such use cases, they aren't exactly typical for most of the 
classical processing scenarios and patterns. In any case, they aren't typical 
at all for the kind of the software architecture that interests me particularly
and which is the serverless.

As a matter of fact, parallel processing in serverless is done through multi-instance
architecture, not multi-threading. In order to use the multi-threading and to be
able to process multiple independent tasks simultaneously, your serverless 
functions need to be "fat" enough, provisioned with enough CPU and memory, such
that to support the required scale-up. Which would lead to a very expansive 
infrastructure.

As opposed to the multi-threading, the multi-instance is a much more appropriate
and adequate solution for the serverless, where every function consists in a 
single thread and multiple pieces of work are simultaneously processed by several
independent serverless instances.

In conclusion, if like me, your main concern is the serverless and if you believe
that this software architecture is the Graal (not to be confused with GraalVM :-)),
then you may follow my advice and to safely ignore Loom, at least for now.