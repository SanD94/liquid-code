#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(httpuv)
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) {
  stop("usage: r_server.R <manifest-path>")
}

manifest_path <- normalizePath(args[[1]], mustWork = TRUE)
manifest <- fromJSON(manifest_path, simplifyVector = TRUE)

state <- new.env(parent = emptyenv())
state$runtime <- new.env(parent = globalenv())
state$runtime$manifest <- manifest
state$output_limit <- 50L
state$shutdown_requested <- FALSE

write_json <- function(status, payload) {
  list(
    status = status,
    headers = list("Content-Type" = "application/json"),
    body = toJSON(payload, auto_unbox = TRUE, pretty = TRUE, null = "null")
  )
}

session_payload <- function() {
  list(id = manifest$id, backend = manifest$backend, port = manifest$port, started_at = manifest$started_at)
}

parse_body <- function(req) {
  body <- req$rook.input$read()
  if (length(body) == 0) {
    return(list())
  }
  fromJSON(rawToChar(body), simplifyVector = TRUE)
}

parse_query <- function(query) {
  if (!nzchar(query)) {
    return(list())
  }
  query <- sub("^\\?", "", query)

  parts <- strsplit(query, "&", fixed = TRUE)[[1]]
  out <- list()
  for (part in parts) {
    pieces <- strsplit(part, "=", fixed = TRUE)[[1]]
    key <- URLdecode(pieces[[1]])
    value <- if (length(pieces) > 1) URLdecode(paste(pieces[-1], collapse = "=")) else ""
    out[[key]] <- value
  }
  out
}

relativize_path <- function(path) {
  artifact_root <- normalizePath(manifest$artifact_dir, mustWork = TRUE)
  resolved <- normalizePath(file.path(artifact_root, path), mustWork = FALSE)
  safe_prefix <- paste0(artifact_root, .Platform$file.sep)
  if (!(identical(resolved, artifact_root) || startsWith(resolved, safe_prefix))) {
    stop("artifact path escapes artifact_dir")
  }
  resolved
}

trim_stdout <- function(lines) {
  total <- length(lines)
  limit <- state$output_limit
  if (total > limit) {
    return(list(lines = lines[seq_len(limit)], truncated = TRUE, total = total))
  }
  list(lines = lines, truncated = FALSE, total = total)
}

list_objects <- function() {
  names <- ls(state$runtime, all.names = TRUE)
  lapply(names, function(name) {
    value <- get(name, envir = state$runtime)
    klass <- paste(class(value), collapse = "/")
    summary <- paste(utils::capture.output(utils::str(value, give.attr = FALSE, max.level = 1L)), collapse = " ")
    list(name = name, class = klass, summary = summary)
  })
}

detect_artifacts <- function(before) {
  after <- list.files(manifest$artifact_dir, full.names = TRUE, all.files = TRUE)
  new_files <- setdiff(after, before)
  lapply(new_files, function(f) {
    info <- file.info(f)
    list(
      path = basename(f),
      size = as.numeric(info$size),
      mtime = as.character(info$mtime)
    )
  })
}

run_eval <- function(code) {
  warnings <- character()
  messages <- character()
  before_artifacts <- list.files(manifest$artifact_dir, full.names = TRUE, all.files = TRUE)

  result <- tryCatch(
    withCallingHandlers(
      {
        stdout <- capture.output(eval(parse(text = code), envir = state$runtime))
        list(ok = TRUE, stdout = stdout, error = NULL)
      },
      warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      },
      message = function(m) {
        messages <<- c(messages, conditionMessage(m))
        invokeRestart("muffleMessage")
      }
    ),
    error = function(err) {
      list(ok = FALSE, stdout = character(), error = conditionMessage(err))
    }
  )

  trimmed <- trim_stdout(result$stdout)
  artifacts <- detect_artifacts(before_artifacts)

  list(
    ok = result$ok,
    stdout = unname(trimmed$lines),
    warnings = unname(warnings),
    messages = unname(messages),
    artifacts = artifacts,
    truncated = trimmed$truncated,
    total_lines = trimmed$total,
    error = result$error,
    session = list(id = manifest$id, port = manifest$port)
  )
}

save_checkpoint <- function() {
  vars <- ls(state$runtime, all.names = TRUE)
  save(list = vars, envir = state$runtime, file = manifest$checkpoint_path)
  list(ok = TRUE, checkpoint_path = manifest$checkpoint_path, session = list(id = manifest$id, port = manifest$port))
}

restore_checkpoint <- function() {
  if (!file.exists(manifest$checkpoint_path)) {
    return(list(ok = FALSE, restored = FALSE, checkpoint_path = manifest$checkpoint_path, error = "checkpoint not found", session = list(id = manifest$id, port = manifest$port)))
  }

  load(manifest$checkpoint_path, envir = state$runtime)
  list(ok = TRUE, restored = TRUE, checkpoint_path = manifest$checkpoint_path, session = list(id = manifest$id, port = manifest$port))
}

read_artifact <- function(req) {
  query <- req$QUERY_STRING
  params <- parse_query(query)
  rel_path <- params$path
  if (is.null(rel_path) || !nzchar(rel_path)) {
    return(write_json(400L, list(ok = FALSE, error = "missing artifact path", session = list(id = manifest$id, port = manifest$port))))
  }

  offset <- as.integer(params$offset %||% 0L)
  limit <- as.integer(params$limit %||% 4096L)
  resolved <- tryCatch(relativize_path(rel_path), error = function(err) err)
  if (inherits(resolved, "error")) {
    return(write_json(400L, list(ok = FALSE, error = conditionMessage(resolved), session = list(id = manifest$id, port = manifest$port))))
  }

  if (!file.exists(resolved)) {
    return(write_json(404L, list(ok = FALSE, error = "artifact not found", session = list(id = manifest$id, port = manifest$port))))
  }

  con <- file(resolved, open = "rb")
  on.exit(close(con), add = TRUE)
  seek(con, where = offset, origin = "start")
  raw <- readBin(con, what = "raw", n = limit)
  text <- rawToChar(raw)

  write_json(200L, list(
    ok = TRUE,
    path = rel_path,
    offset = offset,
    limit = limit,
    bytes_read = length(raw),
    is_text = TRUE,
    content = text,
    session = list(id = manifest$id, port = manifest$port)
  ))
}

`%||%` <- function(x, y) if (is.null(x)) y else x

app <- list(call = function(req) {
  method <- req$REQUEST_METHOD
  path <- req$PATH_INFO

  if (identical(method, "GET") && identical(path, "/health")) {
    return(write_json(200L, list(ok = TRUE, session = session_payload())))
  }

  if (identical(method, "GET") && identical(path, "/objects")) {
    return(write_json(200L, list(ok = TRUE, objects = list_objects(), session = list(id = manifest$id, port = manifest$port))))
  }

  if (identical(method, "GET") && identical(path, "/artifact")) {
    return(read_artifact(req))
  }

  if (identical(method, "POST") && identical(path, "/eval")) {
    body <- parse_body(req)
    code <- body$code %||% ""
    return(write_json(200L, run_eval(code)))
  }

  if (identical(method, "POST") && identical(path, "/checkpoint")) {
    return(write_json(200L, save_checkpoint()))
  }

  if (identical(method, "POST") && identical(path, "/restore")) {
    payload <- restore_checkpoint()
    status <- if (isTRUE(payload$ok)) 200L else 404L
    return(write_json(status, payload))
  }

  if (identical(method, "POST") && identical(path, "/shutdown")) {
    state$shutdown_requested <- TRUE
    return(write_json(200L, list(ok = TRUE, shutting_down = TRUE, session = list(id = manifest$id, port = manifest$port))))
  }

  write_json(404L, list(ok = FALSE, error = sprintf("no route for %s %s", method, path), session = list(id = manifest$id, port = manifest$port)))
})

server <- startServer("127.0.0.1", manifest$port, app)
on.exit(stopServer(server), add = TRUE)

cat(sprintf("r server listening on http://127.0.0.1:%s\n", manifest$port))

while (!isTRUE(state$shutdown_requested)) {
  service(timeoutMs = 100L)
  Sys.sleep(0.05)
}
