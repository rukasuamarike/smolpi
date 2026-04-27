package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/chromedp/cdproto/cdp"
	"github.com/chromedp/chromedp"
)

type Element struct {
	Tag   string            `json:"tag"`
	Text  string            `json:"text,omitempty"`
	Attrs map[string]string `json:"attrs,omitempty"`
}

const selector = `button, a, input, select, textarea, [role="button"], [role="link"], [role="tab"]`

func main() {
	url := "https://example.com"
	if len(os.Args) > 1 {
		url = os.Args[1]
	}

	opts := append(chromedp.DefaultExecAllocatorOptions[:],
		chromedp.Flag("headless", true),
		chromedp.Flag("no-sandbox", true),
		chromedp.Flag("disable-gpu", true),
		chromedp.Flag("disable-dev-shm-usage", true),
	)

	allocCtx, cancel := chromedp.NewExecAllocator(context.Background(), opts...)
	defer cancel()

	ctx, cancel := chromedp.NewContext(allocCtx)
	defer cancel()

	ctx, cancel = context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	var nodes []*cdp.Node
	err := chromedp.Run(ctx,
		chromedp.Navigate(url),
		chromedp.Sleep(2*time.Second),
		chromedp.Nodes(selector, &nodes, chromedp.ByQueryAll),
	)
	if err != nil {
		log.Fatalf("chromedp error: %v", err)
	}

	keep := []string{"id", "class", "aria-label", "role", "href", "type", "name", "placeholder", "value"}
	elements := make([]Element, 0, len(nodes))
	for _, n := range nodes {
		attrs := make(map[string]string)
		for i := 0; i+1 < len(n.Attributes); i += 2 {
			for _, k := range keep {
				if n.Attributes[i] == k {
					attrs[k] = n.Attributes[i+1]
				}
			}
		}
		el := Element{
			Tag:   n.LocalName,
			Attrs: attrs,
		}
		if len(n.Children) > 0 && n.Children[0].NodeType == cdp.NodeTypeText {
			el.Text = n.Children[0].NodeValue
		}
		elements = append(elements, el)
	}

	out, _ := json.MarshalIndent(elements, "", "  ")
	fmt.Println(string(out))
}
