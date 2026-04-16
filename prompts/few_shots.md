# Bridge Kit Few-Shot Examples

## Example: Inspect Shape Before Data

User goal: understand a large table in R.

Good sequence:

```text
POST /eval {"code":"dim(df); names(df); head(df, 5)"}
GET /objects
POST /eval {"code":"write.csv(df, file.path(manifest$artifact_dir, 'df.csv'), row.names = FALSE)"}
GET /artifact?path=df.csv&offset=0&limit=4096
```

Bad sequence:

```text
POST /eval {"code":"print(df)"}
```

## Example: Checkpoint Before Risky Work

User goal: mutate state but keep a recovery point.

Good sequence:

```text
POST /checkpoint {}
POST /eval {"code":"model <- expensive_fit(data)"}
POST /eval {"code":"summary(model)"}
```

## Example: Verify Session Health First

User goal: continue work from an existing session.

Good sequence:

```text
GET /health
POST /restore {}
GET /objects
POST /eval {"code":"ls()"}
```

## Example: End Cleanly

User goal: finish the task and preserve logs.

Good sequence:

```text
POST /checkpoint {}
POST /shutdown {}
```
