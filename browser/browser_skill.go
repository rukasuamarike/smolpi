package main

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"net/url"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	readability "codeberg.org/readeck/go-readability/v2"
	md "github.com/JohannesKaufmann/html-to-markdown"
	"github.com/JohannesKaufmann/html-to-markdown/plugin"
	"github.com/PuerkitoBio/goquery"
)

func envInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func main() {
	pageURL := "https://example.com"
	if len(os.Args) > 1 {
		pageURL = os.Args[1]
	}

	chromeBin := os.Getenv("CHROME_BIN")
	if chromeBin == "" {
		chromeBin = "chromium"
	}
	timeoutSec := envInt("BROWSER_TIMEOUT", 30)
	maxLen := envInt("BROWSER_MAX_OUTPUT", 8000)

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
		pageURL,
	)

	var stdout bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = nil

	if err := cmd.Run(); err != nil {
		log.Fatalf("chromium failed: %v", err)
	}

	html := stdout.Bytes()
	parsedURL, _ := url.Parse(pageURL)

	// Extract interactive elements from full page (readability would strip them)
	interactive := extractInteractive(bytes.NewReader(html))

	// Run readability on the same HTML for clean content
	article, err := readability.FromReader(bytes.NewReader(html), parsedURL)
	if err != nil {
		log.Printf("readability failed: %v (falling back to interactive only)", err)
	}

	// Convert article body to markdown via html-to-markdown
	conv := md.NewConverter("", true, nil).Use(plugin.GitHubFlavored())
	body := ""
	if article.Node != nil {
		var bodyHTML bytes.Buffer
		if err := article.RenderHTML(&bodyHTML); err == nil {
			body, err = conv.ConvertString(bodyHTML.String())
			if err != nil {
				log.Printf("md conversion failed: %v", err)
			}
			body = strings.TrimSpace(body)
		}
	}

	out := strings.Builder{}
	title := strings.TrimSpace(article.Title())
	if title != "" {
		fmt.Fprintf(&out, "# %s\n\n", title)
	}
	fmt.Fprintf(&out, "Source: %s\n\n", pageURL)

	if len(interactive) > 0 {
		out.WriteString("## Interactive\n")
		for _, line := range interactive {
			out.WriteString("- " + line + "\n")
		}
		out.WriteString("\n")
	}

	if body != "" {
		out.WriteString("## Content\n\n")
		out.WriteString(body)
		out.WriteString("\n")
	} else {
		out.WriteString("_(no readable content found)_\n")
	}

	final := out.String()
	if len(final) > maxLen {
		final = final[:maxLen] + "\n\n[truncated]"
	}
	fmt.Print(final)
}

// extractInteractive returns "[BUTTON: text]" / "[INPUT name=q ...]" / "[LINK text -> href]" lines
// for buttons, inputs, and key links — capped per type.
func extractInteractive(r *bytes.Reader) []string {
	doc, err := goquery.NewDocumentFromReader(r)
	if err != nil {
		return nil
	}

	var lines []string
	seen := map[string]bool{}
	add := func(s string) {
		if s == "" || seen[s] {
			return
		}
		seen[s] = true
		lines = append(lines, s)
	}

	caps := map[string]int{"button": 15, "input": 15, "a": 10, "select": 10, "textarea": 10}
	count := map[string]int{}

	doc.Find(`button, input, select, textarea, a, [role="button"], [role="link"]`).Each(func(_ int, s *goquery.Selection) {
		node := s.Get(0)
		if node == nil {
			return
		}
		tag := node.Data
		if cap, ok := caps[tag]; ok && count[tag] >= cap {
			return
		}

		text := strings.Join(strings.Fields(s.Text()), " ")
		if len(text) > 80 {
			text = text[:80] + "…"
		}
		label, _ := s.Attr("aria-label")
		display := text
		if display == "" {
			display = label
		}

		switch tag {
		case "button":
			if display == "" {
				return
			}
			count[tag]++
			add(fmt.Sprintf("[BUTTON: %s]", display))
		case "input":
			t, _ := s.Attr("type")
			if t == "hidden" {
				return
			}
			name, _ := s.Attr("name")
			ph, _ := s.Attr("placeholder")
			parts := []string{}
			if name != "" {
				parts = append(parts, "name="+name)
			}
			if t != "" {
				parts = append(parts, "type="+t)
			}
			if ph != "" {
				parts = append(parts, fmt.Sprintf("placeholder=%q", ph))
			}
			if label != "" {
				parts = append(parts, fmt.Sprintf("label=%q", label))
			}
			if len(parts) == 0 {
				return
			}
			count[tag]++
			add("[INPUT " + strings.Join(parts, " ") + "]")
		case "select", "textarea":
			name, _ := s.Attr("name")
			if name == "" && label == "" {
				return
			}
			count[tag]++
			add(fmt.Sprintf("[%s name=%s label=%q]", strings.ToUpper(tag), name, label))
		case "a":
			href, _ := s.Attr("href")
			if href == "" || href == "#" || display == "" {
				return
			}
			count[tag]++
			add(fmt.Sprintf("[LINK: %s -> %s]", display, href))
		}
	})

	return lines
}
