# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  import_deps: [:ecto],
  locals_without_parens: [
    # Partial
    defpartial: 2,
    # Schema
    field!: 1,
    field!: 2,
    field!: 3,
    embeds_one!: 2,
    embeds_one!: 3,
    embeds_one!: 4,
    embeds_many!: 2,
    embeds_many!: 3,
    embeds_many!: 4
  ]
]
