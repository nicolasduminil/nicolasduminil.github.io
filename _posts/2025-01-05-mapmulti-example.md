---
title:  "Java Functional Style in FinTech Applications"
categories:
  - Java
  - FinTech
tags:
  - Blog
toc: true
last_modified_at: 2025-01-05T08:05:34-05:00
---

Java isn't a functional programming language like Scala, Haskel or Clojure.
However, since Java 8, i.e. since 2014, Java developers who happen to be fans
of functional programming as well, are spoilt with a new paradigm, allowing
those who have studied Lisp or Prolog at the university, to recall with nostalgia
their early years. As a matter of fact, it is hardly a scoop that, since 2014,
Java also supports a functional style.

This new functional style, that Java supports since its 8th release, is principally
articulated around the *Stream API* which provides a powerful and expressive way
to process sequences and collections of elements as data streams and to offer
effective operations such as filtering, mapping, and reducing.

Starting with Java 16, i.e. since 2021, the *Stream API* has been enriched with
a new operation named `mapMulti()`. The code fragment below shows its signature:

    default <R> Stream<R> mapMulti (BiConsumer<? super T, ? super Consumer<R>> mapper)

This quite cryptical signature tries to express the idea that the `mapMulti()`
operation builds an output stream, by replacing zero or more elements of the input
stream, applying to each one of its elements the mapper passed as its argument.
This mapper is a `BiConsumer` instance which consists, as its name implies, in
two consumers. The first one takes and transforms the required stream elements,
while the 2nd one accepts them.

But why is the `mapMulti()` operation so important that it was worth the effort
to modify the *Streams API* in order to add it ? The documentation states that
it is similar to `flatMap()`, so why taking the trouble to modify the `Stream`
interface just to add a new operation similar to an existent one ?

Well, in order to understand that, the easiest way is to consider an example.
Have a look at this [project](https://github.com/nicolasduminil/mapmulti-example.git). It is inspired from a real business case that I came
across to during my daily activity, working for the FinTech industry.

Have you heard about HF-PIFI ? For those who haven't, it states for *High Frequency
Price-based indicator for Finance Integration* and you can have a full introduction
to it [here](https://shorturl.at/cpE5H). In a nutshell, it has to do with the
Covid-19 crisis and the necessity to have a "thermometer" of the public health
data releases, such that to help to distinguish between the main pandemic phases.
But beyond the pandemics, where HF-PIFI played a major role in monitoring the
correlation between the systemic stress and the financial fragmentation of the
financial markets, this indicator, associated with individual accounts and transactions,
helps to build a single set of statistics, integrating information from the money,
bond equity and retail banking markets and to analyse the financial integration
process, in the Euro area, on a daily basis.

Far from trying to exhaust here all the details and subtleties of this indicator,
let's look at the very simplified example below:

    public class AccountOwner
    {
      private String firstName;
      private String lastName;
      private List<BankAccount> bankAccountList;
      ...
    }

    public class BankAccount
    {
      private String sortCode;
      private String accountNumber;
      private String bankName;
      private BigDecimal hfpifi;
      ...
    }

The code fragment above shows a class hierarchy implementing a one-to-many
relationship between a bank client, as an account owner, and one or more bank
accounts. Each account owner has a list of bank accounts. So a `List<AccountOwner>`
will nest a `List<BankAccount>` for each `AccountOwner`. Moreover, the class below
maps a an `AccountOwner` to a single `BankAccount`:

    public class HfPifi
    {
      private AccountOwner accountOwner;
      private BankAccount bankAccount;
      ...
    }

As a matter of fact, the HF-PIFI indicator needs to be represented by customer
and by account. Hence, customers having several accounts will be represented
by several `HfPifi` instances. So, given a list of account owners with their
associated bank accounts like the one initialized below:

    private List<AccountOwner> getAccountOwners()
    {
      return List.of(
       new AccountOwner("John", "Doe", List.of(
         new BankAccount("sortCode1", "accountNumber1", "Bank1", new BigDecimal("0.78")),
         new BankAccount("sortCode2", "accountNumber2", "Bank2", new BigDecimal("0.56")),
         new BankAccount("sortCode3", "accountNumber3", "Bank3", new BigDecimal("0.61"))
       )),
       new AccountOwner("Jane", "Doe", List.of(
         new BankAccount("sortCode4", "accountNumber4", "Bank4", new BigDecimal("0.43")),
         new BankAccount("sortCode5", "accountNumber5", "Bank5", new BigDecimal("0.24")),
         new BankAccount("sortCode6", "accountNumber6", "Bank6", new BigDecimal("0.69"))
       )),
       new AccountOwner("Mike", "Doe", List.of(
         new BankAccount("sortCode7", "accountNumber7", "Bank7", new BigDecimal("0.71")),
         new BankAccount("sortCode8", "accountNumber8", "Bank8", new BigDecimal("0.84")),
         new BankAccount("sortCode9", "accountNumber9", "Bank9", new BigDecimal("0.32"))
         ))
      );
    }

mapping this one-to-many relationship to a flat `HfPifi` model is a classical
scenario in functional programming. The easiest way to do it is by using `flatMap()`
as follows:

    ...
    List<AccountOwner> accountOwners = getAccountOwners();
    List<HfPifi> hfPifis = accountOwners.stream()
      .flatMap(accountOwner -> accountOwner.getBankAccountList().stream()
        .map(bankAccount -> new HfPifi(accountOwner, bankAccount)))
      .collect(Collectors.toList());
    ...

The problem is that, in order to use `flatMap()`, we need to create a new
intermediate stream for each account owner. And given the large number of
account owners that a financial organization might manage, this becomes very
quickly a huge performance penalty. Only then, after having created this additional
intermediate stream, can we apply the `map()` operation.

This is where our new `mapMulti()` method comes into the play. It doesn't require
this intermediate stream and the mapping is straightforward, as shown below:

    ...
    List<AccountOwner> accountOwners = getAccountOwners();
    List<HfPifi> hfPifis = accountOwners.stream()
      .<HfPifi>mapMulti((accountOwner, consumer) ->
        accountOwner.getBankAccountList()
          .forEach(bankAccount -> consumer.accept(new HfPifi(accountOwner, bankAccount))))
      .collect(Collectors.toList());
    ...

For each account owner, the consumer buffers a number of `HfPifi` instances
equal to the number of the account owner's bank accounts. These instances are
flattened over downstream and are finally collected in a `List<HfPifi>` via the
`toList()` collector.

This implementation illustrates the following important note that the documentation
mentions:

> **_NOTE:_**  The `mapMulti()` operation is useful when replacing each stream
> element with a small (possibly zero) number of elements.

For example, if we need to filter our bank accounts based on their HfPifi rate,
we could implement this as follows:

    ...
    List<AccountOwner> accountOwners = getAccountOwners();
    List<HfPifi> hfPifis = accountOwners.stream()
      .flatMap(accountOwner -> accountOwner.getBankAccountList().stream()
        .filter(bankAccount -> bankAccount.getHfpifi().compareTo(new BigDecimal("0.6")) > 0)
        .map(bankAccount -> new HfPifi(accountOwner, bankAccount)))
      .collect(Collectors.toList());
    ...

As you can see, here we filter the bank account on HF-PIFI rates superior to 0.6.
This example is perfectly suitable for being implemented using `mapMulti()` instead
of `flapMap()` as an account owner has a relatively small number of accounts and
applying a filter on them is straightforward, as shown below:

    ...
    List<AccountOwner> accountOwners = getAccountOwners();
    List<HfPifi> hfPifis = accountOwners.stream()
      .<HfPifi>mapMulti((accountOwner, consumer) ->
        accountOwner.getBankAccountList()
          .forEach(bankAccount ->  {
            if (bankAccount.getHfpifi().compareTo(new BigDecimal("0.6")) > 0)
              consumer.accept(new HfPifi(accountOwner, bankAccount));
          }))
      .collect(Collectors.toList());
    ...

This implementation is much better than the previous one  as it reduces
the number of intermediate operations, by removing `filter()`, and avoids
intermediate streams created by `flatMap()`.

Another rule defined by the documentation states that:

> **_NOTE:_** The `mapMulti()` operation is also useful when an imperative approach
> is preferable against a stream based one.

So, if we add the following method to the `AccountOwner` class:

    public void hfpifi(Consumer<HfPifi> consumer)
    {
      bankAccountList.forEach(account -> {
        if (account.getHfpifi().compareTo(new BigDecimal("0.6")) > 0)
          consumer.accept(new HfPifi(this, account));
      });
    }

then we get the `List<HfPifi>` by simply using `mapMulti()` like this:

    List<HfPifi> hfPifis = getAccountOwners().stream()
      .<HfPifi>mapMulti(AccountOwner::hfpifi)
      .collect(Collectors.toList());

In order to test the project that illustrates these examples, proceed as follows:

    $ git clone https://github.com/nicolasduminil/mapmulti-example.git
    $ cd mapmulti-example
    $ mvn test

A test report showing that all the unit tests have succeeded should be presented to you.

Isn't that cool ?

[![50 Shades of Java Executors](/assets/images/executors.png)](https://shorturl.at/ohTjM)
