package main

import (
	"fmt"
	"net/url"
	"strings"

	"github.com/go-git/go-billy/v5"
	"github.com/go-git/go-git/v5"
	"github.com/go-git/go-git/v5/plumbing"
	"github.com/go-git/go-git/v5/storage/memory"

	"os"
	"path/filepath"
)

func newGitInfo(rawurl string) (*gitInfo, error) {
	u, err := url.Parse(rawurl)
	if err != nil {
		return nil, fmt.Errorf("failed to parse URL %s: %v", rawurl, err)
	}

	pathElems := strings.SplitN(u.Path[1:], "/", 2)
	if len(pathElems) != 2 {
		err := fmt.Errorf("invalid URL path %s - expected https://github.com/:owner/:repository", u.Path)
		return nil, err
	}

	repo := strings.ReplaceAll(pathElems[1], ".git", "")

	u.Path = strings.Join([]string{"/", pathElems[0], repo}, "/")
	git := &gitInfo{
		u:      u,
		owner:  pathElems[0],
		repo:   repo,
		branch: "master",
	}
	return git, nil
}

func clone(path, branch string, fs billy.Filesystem) (*git.Repository, error) {
	return git.Clone(memory.NewStorage(), fs, &git.CloneOptions{
		URL:           path,
		ReferenceName: plumbing.ReferenceName(fmt.Sprintf("refs/heads/%s", branch)),
		Progress:      os.Stdout,
	})
}

func listYAMLs(fs billy.Filesystem, path string) ([]string, error) {
	path = filepath.Clean(path)
	fis, err := fs.ReadDir(path)
	if err != nil {
		return nil, err
	}

	yamls := make([]string, 0)
	for _, fi := range fis {
		name := filepath.Join(path, fi.Name())
		if fi.IsDir() {
			moreYAMLs, err := listYAMLs(fs, name)
			if err != nil {
				return nil, err
			}

			yamls = append(yamls, moreYAMLs...)
			continue
		}

		ext := filepath.Ext(name)
		if ext != ".yml" && ext != ".yaml" {
			continue
		}

		yamls = append(yamls, name)
	}

	return yamls, nil
}
