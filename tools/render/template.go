package main

import _ "embed"

//go:embed templates/policy.adoc
var policyTemplate string

//go:embed templates/index.adoc
var indexTemplate string

//go:embed templates/nav.adoc
var navTemplate string
