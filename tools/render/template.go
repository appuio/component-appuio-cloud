package main

var policyTemplate = "= Policy: `{{ .Policy.ObjectMeta.Name }}`\n" +
	`{{- $annotations := .Policy.ObjectMeta.Annotations }}
{{- $jsonnet := index $annotations "policies.kyverno.io/jsonnet" }}

[abstract]
--
{{ .Title }}
--

[horizontal]
Category:: {{ index $annotations "policies.kyverno.io/category" }}
Minimum Kyverno version:: {{ index $annotations "policies.kyverno.io/minversion" }}
Subject:: {{ index $annotations "policies.kyverno.io/subject" }}
Policy type:: "{{ .Type }}"
Implementation:: {{ .BaseURL }}/{{ $jsonnet }}[{{ $jsonnet }}]

{{ index $annotations "policies.kyverno.io/description" }}

== Policy Definition

.{{ .BaseURL }}/{{ .Path }}[{{ .Path }},window=_blank]
[source,yaml]
----
{{ .YAML }}
----
`

var navTemplate = "* Policies\n" +
	"{{range .Policies }}** xref:references/policies/{{ .FileName }}[Policy: `{{ .Policy.ObjectMeta.Name }}`]\n{{end}}"
