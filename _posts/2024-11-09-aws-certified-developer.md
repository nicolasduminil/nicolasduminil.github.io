---
title:  "AWS Certified Developer \"Official\" Study Guide"
categories:
  - AWS
  - Amazon
tags:
  - LinkedIn
toc: true
last_modified_at: 2024-11-09T08:05:34-05:00
---

I'm seeing often, on this site, posts showing some skepticism concerning the 
certification process and I have to admit that I can't totally disagree.
As a matter of fact, beside being expansive, certifications might be useless 
because:
  - they aren't relevant for beginners, where they can't compensate the lack of experience;
  - they are even less relevant for experienced people who didn't wait for getting certified in order to show their competences.

However, I can understand the professionals who spend 1,000€ to validate their 
expertise, by getting an AWS full track certification, all the more so as, me 
too, in a certain period of my career, I used to be kind of fond of certifications.

But in order to get certified, one needs to pass exams and, in order to facilitate
these exams (and to a certain extent, to make some additional money), editors 
like AWS provide so-called "certifications guides". For example, the "officially"
recommended one for the *AWS Certified Developer Associate (DVA-C01)* exam, which
last edition was published by Wiley in 2019, is almost 1 000 pages and costs 60€.

Far from my intention to update my DVA-C01 certification that I've already passed
in 2021, I had recently the opportunity to read this guide, which I've missed 3
years ago. And, as you probably guessed, I was disappointed. Some of the statements
in this book were so hard to understand for me that, at the first glance, I've 
been wondering whether the authors were native English speakers ? I've checked 
and it appears that, as a matter of fact, most of them are. It's difficult to 
gather examples in a 1 000 pages book but here is one:

Chapter 8 - Infrastructure as Code, page 441, Question 5°, the following text:

> **_NOTE:_** However, it attempts to update the resource result in the failure message ...

should read as:

> **_NOTE:_** However, its attempt to update the resource, results in the failure message ...

as "result" here above is the verb "to result", not the noun "one result". It 
might seem a tinny detail but it completely changes the sentence meaning. Now, 
imagine you're passing this exam, after having disbursed 300€, and you're failing
at it because of a confusing question. It sucks !

Sometimes things are even more severe like wrong answers to the review questions.
Take for example this one: 

Chapter 11 - Refactor to Microservices, page 582, Question 5°:

> **_NOTE:_** You want to design an application that sends a status email every morning to the system administrators. Which option will work ?

The proposed options are: using SMS, using SNS or using Lambda. Here you eliminate
from start the SMS and SNS based options as they aren't sending email (SMTP) 
messages, but MQTT ones, and you go for the AWS Lambda solution, as it allows 
you to send email messages via the SDK. However, the "officially" validated response
is "using an SNS topic". The reason:

> **_NOTE:_** The option is not correct because AWS Lambda does not allow sending outgoing email messages on port 22. Email servers use port 22 for outgoing messages. Port 22 is blocked on Lambda as an antispam measure.

Let's leave on one side the fact that email servers can use any port number, 
not only the 22, if appropriated configured. But what on the earth does the port
number 22 have to do with anything here ? The question was not how to send a 
message on the port number 22 with an AWS Lambda function, but how to send an 
email message ? And AWS Lambda is perfectly able to send email messages via the
SDK. Additionally, using AWS Lambda is the simplest and the most elegant solution,
as opposed to what the "official" guide is instructing.

So, if you failed at this exam and you think that that's because your answers 
weren't scored as they should have been, then you might be right. And it isn't
buying this guide which would help you.