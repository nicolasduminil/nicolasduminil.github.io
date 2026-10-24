---
title: "Using Anthropic evaluation to check Claude Code plugin efficiency"
author: "Nicolas Duminil"
date: 2026-10-23
tags: [claude-code, ai-assisted-development, java, quarkus, spring-boot, apache-camel, jakarta-ee, evaluation]
canonical_url: "https://www.simplex-software.fr/<final-path>"
---

# Measuring What a Claude Code Skill Contributes

## Context

A Claude Code skill is a Markdown document that the assistant loads when a task matches its
description. A collection of skills, agents and hooks can be packaged as a plugin and
distributed through a marketplace. Since the summer of 2026, my development environment has
relied on such a plugin for Java work, consisting in a set of: Spring Boot, Quarkus,
Apache Camel and Jakarta EE agents and skills. This collection started as a small
set of artifacts but, little by little, I extended it such that, after several 
months, it contained 43 files and 17,338 lines.

This raised a precise question: were the stack conventions provided by this plugin
really contributing anything of measurable to the final outcome or could the model,
by its intrinsic general knowledge, infer the same result, with much fewer tokens ?

This article describes how the question was answered thanks to the Anthropic 
evaluation tool, and what the measurements revealed about the skills and about 
the evaluation method itself.

## A criterion for useful skill content

A skill contributes when it changes what the model produces. Four kinds of content satisfy
that criterion:

1. Personal or team conventions, which the model has no means to infer.
2. Facts more recent than the model's training data, such as new versions and renamed
   artifacts.
3. Non-obvious pitfalls and the decisions that avoid them.
4. Corrections to guidance that is wrong elsewhere, including in upstream plugins.

Textbook material, such as the definition of an Enterprise Integration Pattern or the
meaning of an HTTP status code, belongs to what the model already knows. Trying 
to provide this same knowledge in skills consumes between 5,000 and 8,000 tokens
each time a skill loads. Additionally, the given skill might be outdated. For 
example, my files still referenced Spring Boot 3.2.1 months after the move to 
Spring Boot 4.

## Restructuring before measuring

The first step was to collect all the loose folders in `~/.claude`, defining agents,
skills and hooks, to remove the duplicates and to consolidate them in stand-alone
plugins. The result is a marketplace named `simplex-software` that lists five plugins:

| Plugin | Activation |
|---|---|
| `spring-boot-template` | per project |
| `quarkus-template` | per project |
| `java-extras` | user scope, every session |
| `camel` | per project |
| `jakarta-ee` | per project |

The stack plugins take precedence on every conflict. `java-extras` holds personal rules,
cross stack decisions, operational notes and a `UserPromptSubmit` hook that reminds the
model, on every prompt, which skills apply to the detected stack. Activation per project
keeps stacks material out of the sessions that don't use them.

## The measurement method

Claude Code provides `claude plugin eval`, an open source evaluation tool allowing
you to test the pertinence of your skills, agents and plugins. For example, you
might want to evaluate the efficiency of a given Claude Code plugin. In order to
do that you need to define "test cases", that are execution scenarios that specify
an input prompt, the required context or tools, and the logic or criteria for 
determining success.

A case is a directory with a prompt and a set of graders. The harness runs each
case with the plugin and without it, several times per arm, and reports the score
difference. A case whose score difference stays near zero identifies a plugin 
which doesn't contribute much to the content, as the model is already able to 
produce the same result without it. Such a plugin has to be ablated because its
skills add only tokens and nothing else.

Instead of creating new files in the project, each case asked Claude to provide 
the requested code and configuration directly in its answer. Therefore, they 
don't require a prepared sample project, write permission, etc. The graders 
examined the text of the answer. Each case combined three kinds of graders:

1. Regular expressions for the specific facts the skill claims. These cost nothing.
2. A judge model, Claude Haiku by default with three votes, for the overall correctness.
3. A `tool_used` grader that checks whether Claude invoked the skill through the `Skill`
   tool. It shows whether the plugin arm actually loaded the skill. It is excluded from
   the score, because the arm without the plugin has no skill to invoke and would fail it
   in every run, which would inflate the difference.

A case for the Camel plugin illustrates the format. The prompt file:

```markdown
---
name: quarkus-route-test
tags: [camel, quarkus]
max_turns: 8
allowed_tools: [Skill, Read, Glob, Grep]
---

Quarkus 3 project using Camel Quarkus. A RouteBuilder defines route id `process-route`
from `direct:process` to `kafka:processed-orders`. Write a test that verifies one message
reaches the Kafka endpoint without a real Kafka broker being used for that endpoint.
Include the Maven test dependencies.
```

Its regular expression grader, `graders/test-artifact.md`:

```markdown
---
type: regex
pattern: "camel-quarkus-junit(?!5)"
match: contains
---

Uses camel-quarkus-junit, the successor of the deprecated camel-quarkus-junit5.
```

Its judge grader, `graders/judge.md`, whose body is the criterion the judge model applies to
the answer:

```markdown
---
type: llm
---

Pass only if ALL hold:
- test dependency is org.apache.camel.quarkus:camel-quarkus-junit (not camel-quarkus-junit5)
- test extends CamelQuarkusTestSupport, overrides isUseAdviceWith() to return true, advises route "process-route" (mockEndpoints / mockEndpointsAndSkip) and then starts the context
- does not use @MockEndpoints (not available in Camel Quarkus)
- no Thread.sleep
```

Its skill indicator, `graders/skill-fired.md`, which passes when Claude loads a skill whose
name contains `camel`:

```markdown
---
type: tool_used
tool: Skill
input_match: "camel"
---

Indicator only: the plugin skill was loaded.
```

The command runs every case of a plugin, three runs per arm, with a cost ceiling:

```shell
claude plugin eval . -j 3 --no-publish --max-cost-usd 5
```

## First results

Ten cases covered the three own plugins. The table reports the mean score with the plugin,
without it, and the difference. Two scores are corrected for grader defects described in
the next section.

| Plugin | Case | With | Without | Difference |
|---|---|---|---|---|
| camel | Camel Quarkus route test | 1.00 | 0.33 | +0.67 |
| camel | Spring Boot route unit test | 1.00 | 0.33 | +0.67 |
| camel | Spring Boot Kafka integration test | 1.00 | 0.92 | +0.08 |
| jakarta-ee | integration test on WildFly | 0.89 | 0.33 | +0.56 |
| jakarta-ee | pom setup | equal | equal | 0 |
| jakarta-ee | resource, service and injection | equal | equal | 0 |
| java-extras | CircleCI with Testcontainers | 1.00 | 0.33 | +0.67 |
| java-extras | graceful shutdown on Kubernetes | 1.00 | 0.50 | +0.50 |
| java-extras | Spring Boot to Quarkus migration | 1.00 | 0.89 | +0.11 |
| java-extras | Reactor to Mutiny translation | 0.56 | 0.67 | about 0 |

The cases with a large difference show that the plugin had a consistent contribution
to the final result. In the case of Camel, for example, without the plugin the 
model estimated the Maven artifact version as `4.18.0`, whereas the skill states
4.23.0, built on Spring Boot 4.1.1. It also selected the test artifacts 
`camel-test-spring-junit6` instead of `camel-quarkus-junit` with the skill. 
For CircleCI it chose a plain Docker executor, which offers no Docker daemon to
Testcontainers. For graceful shutdown it omitted the arithmetic that relates the
`preStop` delay, the application shutdown timeout and `terminationGracePeriodSeconds`.

The cases with a difference near zero show the opposite pattern. The Reactor to Mutiny
cheat sheet, the Jakarta EE pom and the CDI constructor injection rules describe knowledge
the model already applies correctly. Reading the answers confirmed it: both arms produced
the same code.

## Trimming, and the regression the evaluation caught

The trimming pass removed the content with a difference near zero and reduced the rest to
facts, decisions and pitfalls. The Reactor to Mutiny section disappeared. The Spring Boot to
Quarkus table kept only the rows where a mistake is likely, the Jakarta EE setup became a
short list of facts and The Camel Kafka test skeleton became one sentence.

The second run, performed after the trimming, confirmed that every case with a 
large difference kept a score of 1.00 with the plugin. Only the migration from 
Spring Boot to Quarkus case declined from 1.00 to 0.78 but part of the decline 
came from judge noise. However, a part was genuine: the shortened table
row stated that the Quarkus `@Transactional` annotation has no `readOnly` attribute,
which determined the model to mistakenly remove the read only behavior of the 
original method. Without the skill, the model preserved it through a read only 
Hibernate session.

The corrected rule prescribes that the intended behavior should be achieved via
a read only `Session` with `FlushMode.MANUAL`, or a `org.hibernate.readOnly` 
query hint. A third run of that case, judged by Claude Sonnet with a criterion 
that checks the read only behavior, passed six runs out of six. The episode is 
the strongest argument for the evaluation: a detail that appeared harmless 
changed the generated code, and only the measurement detected it.

## Final state and cost

| Measure | Before | After |
|---|---|---|
| Agent and skill files | 43 | 6 |
| Lines of agent and skill content | 17,338 | 638 |
| Tokens added to every session | about 2,100 | about 520, plus about 150 for each optional plugin enabled in the project |
| Evaluation cases | none | 6, each with a measured difference |

The complete exercise, including the exploratory run, both full runs and the verification
run, cost about 20 US dollars in model usage. A full run of the remaining suite costs about
6 dollars and takes about five minutes with three parallel runs.

## Lessons

1. The useful content of a skill is narrow: versions, renamed artifacts, corrections and
   non-obvious conventions. Explanations of well known frameworks contribute nothing measurable.
2. An evaluation with and without the plugin is inexpensive and decisive. It replaces a
   debate about relevance with a number per case.
3. Graders require the same scrutiny as the skills and a small judge model is inconsistent on long answers.
4. A reduction of content is a change like any other and deserves a regression test. The
   `readOnly` episode demonstrates it.

## Limitations

Each arm ran three times, which indicates a direction rather than a statistically
established effect. The results describe one model at one date. Here, our Camel plugin
pinned the 4.23 version which a later model may know without assistance. This is
precisely why the suite should run again after each model change. The cases reflect
one developer's projects, and the personal rules in `house-rules` were deliberately
left out of the evaluation, since the model has no means of guessing them.

