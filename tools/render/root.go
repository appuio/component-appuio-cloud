package main

import (
	"fmt"
	"log"
	"os"

	"github.com/spf13/cobra"
)

var rootCmd *cobra.Command

func init() {
	rootCmd = &cobra.Command{
		Use:   "render <URL> <dir>",
		Short: "render converts Kyverno policies in the filesystem from YAML to asciidoc files in the supplied directory",
		Args:  cobra.ExactArgs(3),
		Run: func(cmd *cobra.Command, args []string) {
			repoDir, policyDir, outDir, err := validateAndParse(args)
			if err != nil {
				log.Println(err)
				_ = rootCmd.Usage()
				return
			}

			if err := render(repoDir, policyDir, outDir); err != nil {
				log.Println(err)
				return
			}
		},
	}
}

func validateAndParse(args []string) (string, string, string, error) {
	if len(args) != 3 {
		return "", "", "", fmt.Errorf("invalid arguments: %v", args)
	}

	repoDir := args[0]
	if info, err := os.Stat(repoDir); err != nil || !info.IsDir() {
		return "", "", "", fmt.Errorf("repoDir must be a directory")
	}

	policyDir := args[1]
	if info, err := os.Stat(repoDir); err != nil || !info.IsDir() {
		return "", "", "", fmt.Errorf("policyDir must be directory")
	}

	outDir := args[2]
	return repoDir, policyDir, outDir, nil
}
