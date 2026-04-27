package main

import (
	"bytes"
	"context"
	"encoding/json"
	"log"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/PuerkitoBio/goquery"
)

type Element struct {
	Tag   string            `json:"tag"`
	Text  string            `json:"text,omitempty"`
	Attrs map[string]string `json:"attrs,omitempty"`
}

type Output struct {
	URL      string         `json:"url"`
	Title    string         `json:"title,omitempty"`
	Counts   map[string]int `json:"counts"`
	Elements []Element      `json:"elements"`
}

// Interactive controls + content tags (headings, code blocks, paragraphs)
const selector = `button, input, select, textarea, a, ` +
	`[role="button"], [role="link"], [role="tab"], ` +
	`h1, h2, h3, h4, h5, h6, pre, p, li`

var keepAttrs = []string{"aria-label", "role", "href", "type", "name", "placeholder", "value"}

// Per-tag caps tuned for ~5KB total output (Gemma 4 ctx friendly)
var tagCaps = map[string]int{
	"input":    20,
	"button":   20,
	"select":   20,
	"textarea": 20,
	"a":        15,
	"h1":       3,
	"h2":       12,
	"h3":       20,
	"h4":       10,
	"h5":       5,
	"h6":       5,
	"pre":      8,
	"p":        15,
	"li":       30,
}

func envInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func main() {
	url := "https://example.com"
	if len(os.Args) > 1 {
		url = os.Args[1]
	}

	chromeBin := os.Getenv("CHROME_BIN")
	if chromeBin == "" {
		chromeBin = "chromium"
	}
	timeoutSec := envInt("BROWSER_TIMEOUT", 30)
	maxText := envInt("BROWSER_MAX_TEXT", 80)
	// Code/paragraph blocks get a longer text budget than UI labels
	maxLongText := envInt("BROWSER_MAX_LONG_TEXT", 400)

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

	out := Output{
		URL:      url,
		Title:    strings.TrimSpace(doc.Find("title").First().Text()),
		Counts:   map[string]int{},
		Elements: []Element{},
	}

	type key struct{ tag, text, label, href string }
	seen := map[key]bool{}
	perTag := map[string]int{}

	doc.Find(selector).EachWithBreak(func(i int, s *goquery.Selection) bool {
		node := s.Get(0)
		if node == nil {
			return true
		}
		tag := node.Data

		attrs := map[string]string{}
		for _, k := range keepAttrs {
			if v, ok := s.Attr(k); ok && v != "" {
				attrs[k] = v
			}
		}

		// pre tags preserve newlines (code blocks); others collapse whitespace
		var text string
		if tag == "pre" {
			text = strings.TrimSpace(s.Text())
		} else {
			text = strings.Join(strings.Fields(s.Text()), " ")
		}

		// Content tags get the long budget; UI labels stay short
		limit := maxText
		switch tag {
		case "h1", "h2", "h3", "h4", "h5", "h6", "p", "pre", "li":
			limit = maxLongText
		}
		if len(text) > limit {
			text = text[:limit] + "…"
		}

		// Skip noise: no text AND no semantic hint
		hasSignal := text != "" ||
			attrs["aria-label"] != "" ||
			attrs["placeholder"] != "" ||
			attrs["name"] != "" ||
			attrs["value"] != ""
		if !hasSignal {
			return true
		}

		// For <a> tags: require visible text or aria-label (drop icon-only links)
		if tag == "a" && text == "" && attrs["aria-label"] == "" {
			return true
		}

		// For content tags: drop empty/very-short fragments
		switch tag {
		case "h1", "h2", "h3", "h4", "h5", "h6", "p", "pre", "li":
			if len(text) < 3 {
				return true
			}
			// Don't carry attrs on content tags — just text
			attrs = nil
		}

		// Dedupe (same tag + text + label + href is one entry)
		k := key{tag, text, attrs["aria-label"], attrs["href"]}
		if seen[k] {
			return true
		}
		seen[k] = true

		// Per-tag cap
		cap := tagCaps[tag]
		if cap > 0 && perTag[tag] >= cap {
			return true
		}
		perTag[tag]++
		out.Counts[tag]++

		out.Elements = append(out.Elements, Element{
			Tag:   tag,
			Text:  text,
			Attrs: attrs,
		})
		return true
	})

	enc := json.NewEncoder(os.Stdout)
	if os.Getenv("BROWSER_PRETTY") == "1" {
		enc.SetIndent("", "  ")
	}
	enc.Encode(out)
}
