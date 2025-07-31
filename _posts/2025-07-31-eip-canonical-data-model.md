---
title:  "EIP: Back to Fundamentals - The Canonical Data Model"
categories:
  - Java
  - Apache Camel
  - Quarkus
  - EIP
tags:
  - Blog
toc: true
last_modified_at: 2025-07-31T08:05:34-05:00
---

This project demonstrates how to implement a simple, yet realistic, business case
that uses the Canonical Data Model enterprise pattern.

## Scenario

An online marketplace aggregates products from multiple suppliers with different
data formats:

  - Supplier A (Electronics): JSON format with nested specifications.
  - Supplier B (Fashion): XML format with size/color variants.
  - Supplier C (Books): CSV format with ISBN/author details.

All supplier formats are transformed to a canonical `Product` model for unified
catalog management, search, and display.

### Sample Data Format for Supplier A

This supplier uses JSON as the data format.

    {
      "item_id": "ELEC001",
      "name": "Gaming Laptop",
      "cost": 1299.99,
      "specs": {"cpu": "Intel i7", "ram": "16GB"}
    }

### Sample Data Format for Supplier B

This supplier uses XML as the data format.

    <product>
      <sku>FASH002</sku>
      <title>Designer Jacket</title>
      <price>299.50</price>
      <variants>
        <variant size="M" color="Blue"/>
      </variants>
    </product>

### Sample Data Format for Supplier C

This supplier uses CSV as the data format.

    isbn,book_title,author,retail_price
    978-0134685991,Effective Java,Joshua Bloch,45.99

## Architecture

The diagram below shows the software architecture of the implementation:

![Canonical Data Model](/assets/images/canonical-data-model.png)

Everything starts with the `ProductGeneratorProcessor` which generates random
test products in JSON, XML or CSV notation. So, supplier A provides
electronics products in JSON format, supplier B fashion ones in XML format, as for
the supplier C, they provide books in CSV format.

The messages are generated on a time based frequency, one every 15 seconds, using
the `timer` Camel component. Once generated, these messages are passed to a CBR
(*Content Based Router*) which marshals each payload to its
Java corresponding record type, as follows:

  - JSON messages, coming from the Supplier A, are marshaled to instances of `ElectronicsProduct` record type;
  - XML messages, coming from the supplier B, are marshaled to instances of `FashionProduct` record type;
  - CSV messages, coming from the supplier C, are marsheled to instances of `BookProduct` record type.

These Java record instances are further processed by dedicated processors, as
follows:

  - `ElectricsProduct` instances are trasformed by the `ElectronicsTransformer` processor to `Product` canonical instances;
  - `FashionProduct` instances are transformed by the `FashionTransformer` processor to canonical `Product` instances;
  - `BookProduct` instances are transformed by the `BookTransformer` processor to canonical `Product` instances.

All these processors are subclasses of the abstarct class `ProductTransformer`
which implements the transformation general strategy, while bein specialized
by each concrete subclass.

Last but not least, the `Product` instances, ready to be shipped, are just
printed out in the Camel log file. In a real case, of course, they would have
been sent to a delivery channel.

## Flow

The following sequence diagram is illustrating the implementation's flow:

![Canonical model sequence diagram](/assets/images/canonical-sd.png)

## Key Components

  - **Generators**. A set of generators are available in order to generate test data. They generate data in a supplier specific format, i.e. JSON for the Supplier A, XML for the supplier B and CSV for the supplier C. They all implement the `ProductGenerator` interface. See the class diagram below:

![Canonical model generators class diagram](/assets/images/canonical-generator-cd.png)

  - **Transformers**. A set of transformers responsible for mapping the specific data model to the canonical one. See the class diagram below:

![Canonical model transformers class diagram](/assets/images/canonical-transformer-cd.png)

  - **BookProduct**. A record modeling a Supplier C specific product representation.
  - **ElectronicsProduct**. A record modeling a Supplier A specific product representation.
  - **FashionProduct**. A record modeling a Supplier B specific product representation.
  - **Product**. A record modeling a canonical product representation.
  - **ProductCatalogRoute**. The Camel main route. Its listing is shown below:

Here below is the listing of the `ProductCatalogRoute` class which defines the
Camel routes required by our implementation.

    @ApplicationScoped
    public class ProductCatalogRoute extends RouteBuilder
    {
      @Override
      public void configure() throws Exception
      {
        from("timer:generator?period=15000")
         .routeId("dataGenerationRoute")
         .autoStartup(false)
         .process("productGenerator")
         .to("direct:processProduct");
       from("direct:processProduct")
        .routeId("dataProcessingRoute")
        .choice()
          .when(header("supplierType").isEqualTo("ELECTRONICS"))
            .unmarshal().json(JsonLibrary.Jackson, ElectronicsProduct.class)
            .process("electronicsTransformer")
          .when(header("supplierType").isEqualTo("FASHION"))
            .unmarshal().jacksonXml(FashionProduct.class)
            .process("fashionTransformer")
          .when(header("supplierType").isEqualTo("BOOKS"))
            .unmarshal().csv()
            .process("csvToBookTransformer")
            .process("bookTransformer")
        .end()
        .to("log:canonical-product?showBody=true");
      }
    }

## Sample output

    ... Body: Product[id=ELEC001, name=Gaming Laptop, price=1299.99, category=Electronics, attributes={specifications={cpu=Intel i7, ram=16GB}}, supplierId=SUPPLIER_A]]
    ... Body: Product[id=FASH002, name=Designer Jacket, price=299.50, category=Fashion, attributes={variants=[Variant[size=M, color=Blue]]}, supplierId=SUPPLIER_B]]
    ... Body: Product[id=ELEC001, name=Gaming Laptop, price=1299.99, category=Electronics, attributes={specifications={cpu=Intel i7, ram=16GB}}, supplierId=SUPPLIER_A]]
    ... Body: Product[id=FASH002, name=Designer Jacket, price=299.50, category=Fashion, attributes={variants=[Variant[size=M, color=Blue]]}, supplierId=SUPPLIER_B]]
    ... Body: Product[id=FASH002, name=Designer Jacket, price=299.50, category=Fashion, attributes={variants=[Variant[size=M, color=Blue]]}, supplierId=SUPPLIER_B]]
    ... Body: Product[id=978-0134685991, name=Effective Java, price=45.99, category=Books, attributes={author=Joshua Bloch}, supplierId=SUPPLIER_C]]
    ... Body: Product[id=FASH002, name=Designer Jacket, price=299.50, category=Fashion, attributes={variants=[Variant[size=M, color=Blue]]}, supplierId=SUPPLIER_B]]


## Key Patterns Demonstrated

- **Canonical Data Model**: Transforms messages from a supplier specific format to the common canonical one.
- **Message Transformer**: Effectivelly performs messages transformation from a source to a target format.
- **Content-Based Router**: Routes messages to the appropriate Message Transformer.
