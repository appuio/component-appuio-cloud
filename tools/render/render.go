package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"text/template"

	"github.com/go-git/go-billy/v5/osfs"
	"github.com/go-git/go-git/v5"
	kyvernov1 "github.com/kyverno/kyverno/api/kyverno/v1"
	"k8s.io/apimachinery/pkg/util/yaml"
)

type gitInfo struct {
	u      *url.URL
	owner  string
	repo   string
	branch string
}

type policyData struct {
	Title    string
	Policy   *kyvernov1.ClusterPolicy
	YAML     string
	Types    []string
	BaseURL  string
	Path     string
	FileName string
}

type navData struct {
	Policies []*policyData
}

func getPolicyTypes(p *kyvernov1.ClusterPolicy) []string {
	ptypes := map[string]bool{
		"generate": false,
		"mutate":   false,
		"validate": false,
	}
	for _, rule := range p.Spec.Rules {
		if rule.Generation.ResourceSpec.Kind != "" {
			ptypes["generate"] = true
		}
		if rule.Mutation.RawPatchStrategicMerge != nil || rule.Mutation.PatchesJSON6902 != "" {
			ptypes["mutate"] = true
		}
		if rule.Validation.Message != "" {
			ptypes["validate"] = true
		}
	}
	etypes := []string{}
	for t, e := range ptypes {
		if e {
			etypes = append(etypes, t)
		}
	}
	sort.Strings(etypes)
	return etypes
}

func newPolicyData(p *kyvernov1.ClusterPolicy, rawYAML, baseURL, path string) *policyData {
	return &policyData{
		Title:    buildTitle(p),
		Policy:   p,
		YAML:     rawYAML,
		Types:    getPolicyTypes(p),
		BaseURL:  baseURL,
		Path:     path,
		FileName: strings.ReplaceAll(filepath.Base(path), filepath.Ext(path), ".adoc"),
	}
}

func buildTitle(p *kyvernov1.ClusterPolicy) string {
	name := p.Annotations["policies.kyverno.io/title"]
	if name != "" {
		return name
	}

	name = p.Name
	title := strings.ReplaceAll(name, "-", " ")
	title = strings.ReplaceAll(title, "_", " ")
	return strings.Title(title)
}

func render(repodir, policydir, outdir string) error {
	fs := osfs.New(repodir)
	yamls, err := listYAMLs(fs, filepath.Join("/", policydir))
	if err != nil {
		return fmt.Errorf("failed to list YAMLs in repo %s: %v", repodir, err)
	}

	repo, err := git.PlainOpen(filepath.Join(repodir, ".git"))
	if err != nil {
		return fmt.Errorf("unable to open git repo in %s: %v", repodir, err)
	}
	origin, err := repo.Remote("origin")
	if err != nil {
		return fmt.Errorf("unable to lookup remote \"origin\" in %s: %v", repodir, err)
	}
	repourl := origin.Config().URLs[0]
	git, err := newGitInfo(repourl)
	if err != nil {
		return fmt.Errorf("unable to parse remote URL for %s: %v", repodir, err)
	}

	sort.Strings(yamls)
	log.Printf("retrieved %d YAMLs in repository directory %s", len(yamls), repodir)

	t := template.New("policy")
	t, err = t.Parse(policyTemplate)
	if err != nil {
		return fmt.Errorf("failed to parse template: %v", err)
	}

	nd := navData{
		Policies: []*policyData{},
	}
	for _, yamlFilePath := range yamls {
		file, err := fs.Open(yamlFilePath)
		if err != nil {
			log.Printf("Error: failed to read %s: %v", yamlFilePath, err.Error())
			continue
		}

		bytes, err := ioutil.ReadAll(file)
		if err != nil {
			log.Printf("Error: failed to read file %s: %v", file.Name(), err.Error())
		}

		policyBytes, err := yaml.ToJSON(bytes)
		if err != nil {
			log.Printf("failed to convert to JSON: %v", err)
			continue
		}

		policy := &kyvernov1.ClusterPolicy{}
		if err := json.Unmarshal(policyBytes, policy); err != nil {
			log.Printf("failed to decode file %s: %v", yamlFilePath, err)
			continue
		}

		if !(policy.TypeMeta.Kind == "ClusterPolicy" || policy.TypeMeta.Kind == "Policy") {
			continue
		}

		relPath := strings.ReplaceAll(yamlFilePath, "\\", "/")
		pathElems := []string{git.owner, git.repo, "tree", git.branch}
		baseURL := "https://github.com/" + strings.Join(pathElems, "/")

		pd := newPolicyData(policy, string(bytes), baseURL, relPath)
		outFile, err := createOutFile(outdir, "pages/references/policies", filepath.Base(file.Name()))
		if err != nil {
			return err
		}

		if err := t.Execute(outFile, pd); err != nil {
			log.Printf("ERROR: failed to render policy %s: %v", policy.Name, err.Error())
			continue
		}

		nd.Policies = append(nd.Policies, pd)
		log.Printf("rendered %s", outFile.Name())
	}

	it := template.New("index")
	it, err = it.Parse(indexTemplate)
	if err != nil {
		return fmt.Errorf("failed to parse template: %v", err)
	}
	indexFile, err := createOutFile(outdir, "pages/references/policies", "index.adoc")
	if err != nil {
		return err
	}
	if err := it.Execute(indexFile, nd); err != nil {
		log.Printf("ERROR: failed to render index: %v", err.Error())
	}

	nt := template.New("nav")
	nt, err = nt.Parse(navTemplate)
	if err != nil {
		return fmt.Errorf("failed to parse template: %v", err)
	}
	navFile, err := createOutFile(outdir, "partials", "nav-policy.adoc")
	if err != nil {
		return err
	}
	if err := nt.Execute(navFile, nd); err != nil {
		log.Printf("ERROR: failed to render nav: %v", err.Error())
	}

	return nil
}

func createOutFile(docsDir, docsPath, fileName string) (*os.File, error) {
	path := filepath.Join(docsDir, docsPath)
	if err := os.MkdirAll(path, 0744); err != nil {
		return nil, fmt.Errorf("failed to create path %s", path)
	}

	out := filepath.Join(path, strings.ReplaceAll(fileName, filepath.Ext(fileName), ".adoc"))
	outFile, err := os.Create(out)
	if err != nil {
		return nil, fmt.Errorf("failed to create file %s: %v", path, err)
	}

	return outFile, nil
}
