Kitchen Sink
============

A document that exercises every construct LUAM renders. Open it next to the
preview to eyeball the output, or let `KitchenSinkTests` smoke-test it.

## Inline formatting

Plain, *emphasis*, **strong**, ***both***, ~~struck~~, `code`, and a
hard break at the end of this line  
followed by an escaped \*asterisk\* and an entity: &copy; 2026.

Links: [inline](https://example.com "Example"), [reference][ref],
<https://autolink.example>, www.bare.example, and ![an image](image.png).

[ref]: https://example.com/reference

## Headings

### Level three
#### Level four
##### Level five
###### Level six

## Lists

- Bullet one
- Bullet two
  - Nested bullet
  - Another nested
- Bullet three

1. First
2. Second
3. Third

7) Starts at seven
8) Continues

- [ ] Open task
- [x] Finished task

* A loose list item

* With a paragraph gap

## Block quotes

> A quote with **formatting**.
>
> > And a nested quote.

## Code

```swift
@MainActor
struct Greeter {
    let name: String // who to greet
    func greet() -> String { "Hello, \(name)!" }
}
```

```bash
# install
echo "$HOME" && ls -la
```

```json
{ "key": "value", "count": 3, "ok": true }
```

    indented code block

## Table

| Left | Center | Right |
|:-----|:------:|------:|
| a    | b      | c     |
| `x`  | *y*    | 1.5   |

## HTML

<details>
<summary>Raw HTML block</summary>

Hidden content.

</details>

Inline <kbd>⌘</kbd><kbd>S</kbd> HTML.

---

Emoji and wide text: 👩‍💻 **works** — 日本語も。
