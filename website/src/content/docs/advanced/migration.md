---
title: Migrate to standard HTTP types
description: Update earlier Gluegun HTTP methods and collected-response types.
---

If you use an earlier API with Gluegun-specific HTTP methods or
non-generic collected responses, update these types when you upgrade.

## HTTP methods

Import `gleam/http` for `http.Get`, `http.Post`, and other methods. Replace
`request.Method` with `http.Method` and `request.Custom` with `http.Other`.
Add `gleam_http = ">= 4.0.0 and < 5.0.0"` to packages that import these modules.

## Collected responses

Update collected-response annotations from `response.Response` to
`response.Response(BitArray)`. Replace `response.Informational(status, headers)`
with standard `http_response.Response(status, headers, Nil)` values.
The Gluegun status, headers, body, and text accessors remain available.

## Request behavior

Request paths and body builders keep their existing behavior. The current API
uses one total timeout budget for dispatch and response collection.

See [Basic Requests](/guides/basic-requests/) for request and response examples,
and the [client reference](/reference/gluegun-client/) for all high-level client functions.
