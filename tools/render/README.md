# Render

This folder contains a Golang program to convert Kyverno policies YAML definitions to asciidoc that can be included in the component documentation.

The program reads policies from the local filesystem and uses built-in templates.

The templates are stored in folder `templates/` and embedded in the binary using go-embed.

## License

This tool has been adapted from [Kyverno](https://github.com/kyverno/website) and is licensed under the Apache License 2.0

## Build

```sh
cd tools/render
go build
```

## Usage

Execute locally and render the asciidoc into the `docs/modules/ROOT` folder:

```sh
# Run render as built locally. Move into PATH if desired. May need to add execute bit.
tools/render/render . tests/golden/defaults/appuio-cloud/appuio-cloud docs/modules/ROOT
```

## Extend

To expose more data inside the generated policies markdown file, edit the template files in `templates/`
