package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/PuerkitoBio/goquery"
)

type Element struct {
	Tag   string            `json:"tag"`
	Text  string            `json:"text,omitempty"`
	Attrs map[string]string `json:"attrs,omitempty"`
}

const selector = `button, a, input, select, textarea, [role="button"], [role="link"], [role="tab"]`

var keepAttrs = []string{"id", "class", "aria-label", "role", "href", "type", "name", "placeholder", "value"}

func main() {
	url := "https://example.com"
	if len(os.Args) > 1 {
		url = os.Args[1]
	}

	chromeBin := os.Getenv("CHROME_BIN")
	if chromeBin == "" {
		chromeBin = "chromium"
	}

	timeoutSec := 30
	if t := os.Getenv("BROWSER_TIMEOUT"); t != "" {
		fmt.Sscanf(t, "%d", &timeoutSec)
	}

	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutSec)*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, chromeBin,
		"--headless",
		"--no-sandbox",
		"--disable-setuid-sandbox",
		"--disable-dev-shm-usage",
		"--disable-gpu",
		"--virtual-time-budget=5000",
		"--dump-dom",
		url,
	)

	var stdout bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = nil

	if err := cmd.Run(); err != nil {
		log.Fatalf("chromium failed: %v", err)
	}

	doc, err := goquery.NewDocumentFromReader(&stdout)
	if err != nil {
		log.Fatalf("html parse failed: %v", err)
	}

	elements := []Element{}
	doc.Find(selector).Each(func(i int, s *goquery.Selection) {
		node := s.Get(0)
		if node == nil {
			return
		}

		attrs := map[string]string{}
		for _, k := range keepAttrs {
			if v, ok := s.Attr(k); ok && v != "" {
				attrs[k] = v
			}
		}

		text := strings.TrimSpace(s.Text())
		text = strings.Join(strings.Fields(text), " ")
		if len(text) > 200 {
			text = text[:200] + "…"
		}

		elements = append(elements, Element{
			Tag:   node.Data,
			Text:  text,
			Attrs: attrs,
		})
	})

	out, _ := json.MarshalIndent(elements, "", "  ")
	fmt.Println(string(out))
}
