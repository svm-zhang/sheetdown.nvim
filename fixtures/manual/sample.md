# Sheetdown Manual Test

Plain text path:
../data/people.csv

Inline code path:
`../data/quoted.csv`

## Fenced code block

Fenced code block path:

```text
../data/people.tsv
```



## Ambiguous

`../data/ambiguous.csv`


## Malformed body

```
../data/malformed_body.tsv
```

## Ambiguous case 2

This reveals the current implementation problem: `../data/ambiguous.case_2.csv`

## sheetdown.test.csv

This shows the problem of column selection UI:

```
../data/sheetdown.test.tsv
```
