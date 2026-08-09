# Ordering a shelf

Three pictures, a table and a code block, so that a fence's neighbours are
exercised as well as the fence.

## What happens when an order arrives

```mermaid
flowchart TD
    A[Order placed] --> B{In stock?}
    B -- Yes --> C[Pack it]
    B -- No --> D[Order the timber]
    D --> C
    C --> E[Tell the customer]
```

## Who says what to whom

| Step | Who | How long |
|---|---|---:|
| Accept the order | Shop | 1 min |
| Cut the **timber** | Workshop | 2 h |
| Post it | Courier | 1 d |

```mermaid
sequenceDiagram
    autonumber
    Customer->>Shop: Order a shelf
    Shop->>Workshop: Cut the timber
    Workshop-->>Shop: Ready
    Shop-->>Customer: On its way
```

## What the order itself is

```swift
struct Order {
    let part: String
    let quantity: Int
}
```

## The states an order goes through

```mermaid
stateDiagram-v2
    [*] --> Placed
    Placed --> Cutting
    Cutting --> Packed
    Packed --> Sent
    Sent --> [*]
```

That is the whole of it.
