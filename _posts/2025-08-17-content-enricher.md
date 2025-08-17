---
title:  "EIP: Back to Fundamentals - The Content Enricher"
categories:
  - Java
  - Quarkus
  - Apache Camel
  - EIP
tags:
  - Blog
toc: true
last_modified_at: 2025-08-17T08:05:34-05:00
---
## The Content Enricher

Let's continue with the next integration pattern in alphabetical order. We skip the Channel Adapter and the Content Based
Router, that we have already seen in the two previous modules, `aggregator` and `canonical-data-model`, so let's go to the next
relevant one which is the Content Enricher. The name of the module is, with no surprises, `content-enricher`.

### Scenario

The business scenario chosen to illustrate this pattern is presented below:

![Content enricher diagram](/assets/images/content-enricher.png)

Here we're coming back to our business scenario previously used to illustrate the Aggregator pattern. The same order
generator is reused here to generate several random orders. Once generated, these orders are submitted to an enrichment
process. A Camel enricher is implemented by the `enrich` DSL statement, which uses the following two components:

  - an enrichment source responsible to provide the enrichment data;
  - an enrichment aggregator which, on the behalf of its aggregation strategy, describes the enrichment logic.

Our orders enrichment process happens in two stages:

  - in the 1st stage, the order item enricher source is called to provide the required data for the order items enrichment. Then, the order item aggregator effectively performs the enrichment operations, by adding the enrichment data to the existent one;
  - in the 2nd stage, is the turn of the order itself to be enriched. In a similar way, the order enrichment source is called to provide the enrichment data, after which the order enrichment aggregator performs the enrichment.

The Content Enricher pattern beauty consists in its ability to progressively add data from external sources, while
maintaining a clean separation between the enricher itself, its source and its aggregation strategy.

### Architecture

The diagram below shows the software architecture of the implementation:

![Content enricher sequence diagram](/assets/images/content-enricher-sd.png)

As you can see, the two stages of the enrichment process are distinctly represented here. The `EcommerceRoute` class is
our Camel `RouteBuilder`. It uses our old friend `OrderGeneratorProcessor` to generate orders and the
`OrderItemEnrichmentService`, together with `OrderItemEnrichmentStrategy`, to construct orders having their `enrichedItems`
properties enriched with the product details. Then, on the behalf of `OrderEnrichmentService` and `OrderEnrichmentStrategy`,
it enriches the orders themselves, by adding to them the customer details.

### Key components

There are two categories of key components for this implementation: the enrichment source services and the enrichment
strategies. The enrichment source services are simulated in our case. For example, the `OrderEnrichmentService` is as
simple as that:

    @ApplicationScoped
    @Named("orderEnrichmentService")
    public class OrderEnrichmentService implements Processor
    {
      @Override
      public void process(Exchange exchange) throws Exception
      {
        CustomerDetails customerDetails = new CustomerDetails(
          "John Doe",
          "john@example.com",
          "GOLD"
        );
        exchange.getIn().setBody(customerDetails);
      }
    }

In a real application, these enrichment data should probably be extracted from a data store or provided by invoking some
API endpoints. In our simple case, which is a test case, we are just hard coding them. A point to notice is the fact that
a Camel enrichment source only provides the enrichment data and, accordingly, it isn't responsible for effectively doing
the enrichment process. This is the role of the aggregation strategies which, in some cases may be quite simple, as shown
below:

    @ApplicationScoped
    @Named("orderEnrichmentStrategy")
    public class OrderEnrichmentStrategy implements AggregationStrategy
    {
      @Override
      public Exchange aggregate(Exchange original, Exchange enrichment)
      {
        EnrichedOrder enrichedOrder = original.getIn().getBody(EnrichedOrder.class);
        CustomerDetails customerDetails = enrichment.getIn().getBody(CustomerDetails.class);
        original.getIn().setBody(enrichedOrder.withCustomerDetails(customerDetails));
        return original;
      }
    }

Here the aggregation strategy is really straightforward as it consists in simply enriching the order with customer
details. But some other times the strategy is much more complicated, as for example when enriching the enriched order
items of the enriched orders, by adding to them the product details.

    @ApplicationScoped
    @Named("orderItemEnrichmentStrategy")
    public class OrderItemEnrichmentStrategy implements AggregationStrategy
    {
      @Override
      public Exchange aggregate(Exchange original, Exchange enrichment)
      {
        Order order = original.getIn().getBody(Order.class);
        Map<String, ProductDetails> productMap = enrichment.getIn().getBody(Map.class);
        //
        // Transform order items to enriched order items:
        //   find matching product details for each item,
        //   create EnrichedOrderItem if match found,
        //   filter out items without matches
        //
        List<EnrichedOrderItem> enrichedItems = order.items().stream()
          .map(item -> findProductDetails(productMap, item.productId())
          .map(pd -> new EnrichedOrderItem(item, pd)))
          .filter(Optional::isPresent)
          .map(Optional::get)
          .toList();
        EnrichedOrder fullyEnriched = new EnrichedOrder(
          order.orderId(),
          order.customerId(),
          order.shippingAddress(),
          order.orderDate(),
          null,
          enrichedItems
        );
        original.getIn().setBody(fullyEnriched);
        return original;
      }

      private Optional<ProductDetails> findProductDetails(Map<String, ProductDetails> productMap, String productId)
      {
        //
        // Extract the product ID prefix
        //
        String productPrefix = productId.split("-")[0];
        //
        // Returns the `ProductDetails` instance which ket name starts
        // with the prefix ID prefix.
        //
          return productMap.entrySet().stream()
            .filter(entry -> entry.getKey().startsWith(productPrefix))
            .map(Map.Entry::getValue)
            .findFirst();
      }
    }

As you can see, the difficulty here consists in the fact that we need to find the product details that match the order
items that we want to enrich, hence these quite convoluted filters and maps statements. This might not be necessary in
a real case where the enricment source is a data store and, hence, provides a query language, be it SQL or NoSQL.

### Testing

Camel routes are easy to test using the Hawtio console, as we've seen precedently. Quarkus provides a test framework
covering the wide spectrum, fom unit to E2E, passing through integration tests.
For example, look at the following integration test:

    @QuarkusTest
    public class TestEcommerceRoute
    {
      @Inject
      CamelContext camelContext;

      @Inject
      ProducerTemplate producerTemplate;

      @Test
      public void testContentEnricherDemo() throws Exception {
        Order testOrder = new Order(
          "BOOK-1820",
          "CUST-123",
          "123 Test St",
          LocalDateTime.now(),
          List.of(new OrderItem("BOOK-1", "Computer book",
            "SUPPLIER_BOOKS", 1, new BigDecimal(41.75)))
          );
        Exchange result = producerTemplate.request("direct:enrichOrder",
        exchange -> exchange.getIn().setBody(testOrder));
        EnrichedOrder enrichedOrder = result.getIn().getBody(EnrichedOrder.class);
        assertNotNull(enrichedOrder, "Enriched order should not be null");
        assertEquals("BOOK-1820", enrichedOrder.orderId());
        assertNotNull(enrichedOrder.customerDetails(), "Customer details should be enriched");
        assertFalse(enrichedOrder.enrichedItems().isEmpty(), "Items should be present");
        EnrichedOrderItem enrichedItem = enrichedOrder.enrichedItems().get(0);
        assertNotNull(enrichedItem.productDetails(), "Product details should be enriched");
      }
    }

As you can see, instead of using mocks, we're using here real Camel routes and processors. It's a special kind of
integration tests, unique to Quarkus, which runs in the same JVM as the test runner, which by the way, allows us to
inject the `CamelContext`, as well as the `ProducerTemplate`.

Quarkus also provides the `@QuarkusIntegrationTest` annotation which, as opposed to what its name implies,
doesn't annotate integration tests, but E2E ones. Sometimes, the Quarkus naming is indeed confusing and counterintuitive.
This is a common complaint in the community.

### Sample output

    2025-08-16 00:07:04,144 INFO  [contentEnricherDemo] (Camel (camel-1) thread #1 - timer://orderGenerator) === ORDER ===
    2025-08-16 00:07:04,216 INFO  [contentEnricherDemo] (Camel (camel-1) thread #1 - timer://orderGenerator) Order {orderId = 'ORD-1755295624138', customerId = 'CUST-801', items = 5}
    2025-08-16 00:07:04,216 INFO  [content-enricher] (Camel (camel-1) thread #1 - timer://orderGenerator) Exchange[ExchangePattern: InOnly, BodyType: fr.simplex_software.ecommerce.model.Order, Body: Order {orderId = 'ORD-1755295624138', customerId = 'CUST-801', items = 5}]
    2025-08-16 00:07:04,226 INFO  [orderItemEnrichment] (Camel (camel-1) thread #1 - timer://orderGenerator)         >>> Product details retrieved: {BOOK-1=ProductDetails[name=Java Guide, price=45.99, category=Books, stockLevel=100], FASHION-1=ProductDetails[name=T-shirt, price=19.99, category=Fashion, stockLevel=200], LAPTOP-1=ProductDetails[name=Gaming Laptop, price=1299.99, category=Electronics, stockLevel=25]}
    2025-08-16 00:07:04,230 INFO  [orderEnrichment] (Camel (camel-1) thread #1 - timer://orderGenerator)     >>> Customer details retrieved: CustomerDetails[name=John Doe, email=john@example.com, loyaltyTier=GOLD]
    2025-08-16 00:07:04,231 INFO  [doEnrichment] (Camel (camel-1) thread #1 - timer://orderGenerator) === ENRICHED ORDER ===
    2025-08-16 00:07:04,238 INFO  [doEnrichment] (Camel (camel-1) thread #1 - timer://orderGenerator) EnrichedOrder[orderId=ORD-1755295624138, customerId=CUST-801, shippingAddress=789 Pine Rd, Marseille, orderDate=2025-08-16T00:07:04.141387943, customerDetails=CustomerDetails[name=John Doe, email=john@example.com, loyaltyTier=GOLD], enrichedItems=[EnrichedOrderItem[orderItem=OrderItem {productId = 'LAPTOP-87', supplierId = 'SUPPLIER_ELECTRONICS', quantity = 2}, productDetails=ProductDetails[name=Gaming Laptop, price=1299.99, category=Electronics, stockLevel=25]]]]
    2025-08-16 00:07:04,239 INFO  [content-enricher] (Camel (camel-1) thread #1 - timer://orderGenerator) Exchange[ExchangePattern: InOnly, BodyType: fr.simplex_software.ecommerce.model.EnrichedOrder, Body: EnrichedOrder[orderId=ORD-1755295624138, customerId=CUST-801, shippingAddress=789 Pine Rd, Marseille, orderDate=2025-08-16T00:07:04.141387943, customerDetails=CustomerDetails[name=John Doe, email=john@example.com, loyaltyTier=GOLD], enrichedItems=[EnrichedOrderItem[orderItem=OrderItem {productId = 'LAPTOP-87', supplierId = 'SUPPLIER_ELECTRONICS', quantity = 2}, productDetails=ProductDetails[name=Gaming Laptop, price=1299.99, category=Electronics, stockLevel=25]]]]]

### Key Patterns Demonstrated

  - Enrichment source services
  - Aggregation strategies (merge original + enrichment data)
  - Route orchestration (coordinate the enrichment flow)
