package search

import (
	"bytes"
	"strings"
)

type LookupResult struct {
	m map[string]bool
}

func newLookupResult() *LookupResult {
	return &LookupResult{
		m: make(map[string]bool),
	}
}

func (s *LookupResult) Add(val string) {
	s.m[val] = true
}

func (s *LookupResult) Merge(s2 *LookupResult) {
	for k := range s2.m {
		s.Add(k)
	}
}

func (r *LookupResult) Intersection(r2 *LookupResult) *LookupResult {
	res := newLookupResult()
	for k := range r.m {
		if _, ok := r2.m[k]; ok {
			res.Add(k)
		}
	}

	return res
}

func (s *LookupResult) ToSlice() []string {
	var out []string
	for k := range s.m {
		out = append(out, k)
	}

	return out
}

type Trie struct {
	children map[rune]*Trie
	values   []string // TODO: Optimize me. Make me a set.
}

func NewTrie() *Trie {
	var t Trie
	t.init()

	return &t
}

func normalizeKey(key string) string {
	return strings.ToLower(key)
}

func (t *Trie) init() {
	t.children = make(map[rune]*Trie)
}

func (t *Trie) add(runes []rune, value string) {
	if len(runes) == 0 {
		t.values = append(t.values, value)
		return
	}

	var child *Trie
	if c, ok := t.children[runes[0]]; ok {
		child = c
	} else {
		child = NewTrie()
		t.children[runes[0]] = child
	}

	child.add(runes[1:], value)
}

func (t *Trie) Add(key string, value string) {
	key = normalizeKey(key)
	runes := bytes.Runes([]byte(key))

	t.add(runes, value)
}

func (t *Trie) DeleteValue(value string) {
	for i, v := range t.values {
		if v == value {
			t.values = append(t.values[:i], t.values[i+1:]...)
			break
		}
	}

	for _, child := range t.children {
		child.DeleteValue(value)
	}
}

func (t *Trie) gatherValues() *LookupResult {
	s := newLookupResult()
	for _, c := range t.children {
		childValues := c.gatherValues()
		s.Merge(childValues)
	}

	for _, val := range t.values {
		s.Add(val)
	}

	return s
}

func (t *Trie) lookup(runes []rune) *LookupResult {
	if len(runes) == 0 {
		return t.gatherValues()
	}

	if c, ok := t.children[runes[0]]; ok {
		return c.lookup(runes[1:])
	}

	return newLookupResult()
}

func (t *Trie) Lookup(key string) *LookupResult {
	key = normalizeKey(key)
	runes := bytes.Runes([]byte(key))

	return t.lookup(runes)
}
