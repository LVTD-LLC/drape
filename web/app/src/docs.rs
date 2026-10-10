//! Repository Markdown, validated and rendered once at startup.
use anyhow::{Context, Result, ensure};
use maud::{Markup, PreEscaped};
use pulldown_cmark::{Event, Options, Parser};
use rust_embed::Embed;
use serde::Deserialize;
use std::collections::HashSet;

#[derive(Clone, Copy, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "kebab-case")]
pub enum Section {
    GettingStarted,
    Features,
    Deployment,
    DeveloperTools,
}

impl Section {
    pub fn title(self) -> &'static str {
        match self {
            Self::GettingStarted => "Getting started",
            Self::Features => "Features",
            Self::Deployment => "Deployment",
            Self::DeveloperTools => "Developer tools",
        }
    }
}

#[derive(Embed)]
#[folder = "content/docs/"]
#[include = "*.md"]
struct Content;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct FrontMatter {
    title: String,
    slug: String,
    description: String,
    order: u32,
    section: Section,
    #[serde(default)]
    draft: bool,
}

pub struct Document {
    pub title: String,
    pub slug: String,
    pub description: String,
    pub path: String,
    pub body: Markup,
    pub section: Section,
    order: u32,
}

pub struct Docs {
    pub welcome: Document,
    pub pages: Vec<Document>,
}

impl Docs {
    pub fn load() -> Result<Self> {
        let sources = Content::iter()
            .map(|name| {
                let file = Content::get(&name).context("embedded docs file missing")?;
                Ok((name.into_owned(), String::from_utf8(file.data.into_owned())?))
            })
            .collect::<Result<Vec<_>>>()?;
        Self::from_sources(sources)
    }

    fn from_sources(sources: Vec<(String, String)>) -> Result<Self> {
        let mut pages = Vec::new();
        let mut slugs = HashSet::new();
        for (name, source) in sources {
            let (meta, page) = parse(&source).with_context(|| format!("invalid docs page {name}"))?;
            ensure!(slugs.insert(meta.slug), "duplicate docs slug in {name}");
            if !meta.draft {
                pages.push(page);
            }
        }
        let welcome_index =
            pages.iter().position(|page| page.slug == "welcome").context("missing published welcome page")?;
        let welcome = pages.remove(welcome_index);
        pages.sort_by(|a, b| a.section.cmp(&b.section).then(a.order.cmp(&b.order)).then_with(|| a.slug.cmp(&b.slug)));
        Ok(Self { welcome, pages })
    }
}

fn parse(source: &str) -> Result<(FrontMatter, Document)> {
    let source = source.replace("\r\n", "\n");
    let source = source.strip_prefix("+++\n").context("expected +++ TOML front matter")?;
    let (front_matter, markdown) = source.split_once("\n+++\n").context("missing closing +++ delimiter")?;
    let meta: FrontMatter = toml::from_str(front_matter)?;
    ensure!(!meta.title.trim().is_empty(), "title is empty");
    ensure!(!meta.description.trim().is_empty(), "description is empty");
    ensure!(!markdown.trim().is_empty(), "body is empty");
    ensure!(
        !meta.slug.is_empty()
            && meta
                .slug
                .split('-')
                .all(|part| !part.is_empty() && part.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())),
        "invalid docs slug"
    );
    let events =
        Parser::new_ext(markdown, Options::ENABLE_STRIKETHROUGH | Options::ENABLE_TABLES).map(|event| match event {
            Event::Html(text) | Event::InlineHtml(text) => Event::Text(text),
            other => other,
        });
    let mut body = String::new();
    pulldown_cmark::html::push_html(&mut body, events);
    let page = Document {
        title: meta.title.clone(),
        slug: meta.slug.clone(),
        description: meta.description.clone(),
        path: if meta.slug == "welcome" { "/docs".into() } else { format!("/docs/{}", meta.slug) },
        body: PreEscaped(body),
        order: meta.order,
        section: meta.section,
    };
    Ok((meta, page))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn source(slug: &str, order: u32, draft: bool) -> (String, String) {
        (
            format!("{slug}.md"),
            format!(
                "+++\ntitle = \"Getting started\"\nslug = \"{slug}\"\ndescription = \"A guide\"\nsection = \"getting-started\"\norder = {order}\ndraft = {draft}\n+++\n\n## Start here\n\nWrite **Rust**.\n\n<script>alert(1)</script>\n"
            ),
        )
    }
    #[test]
    fn embedded_docs_are_valid() {
        let docs = Docs::load().unwrap();
        assert_eq!(docs.welcome.path, "/docs");
        for slug in ["blog", "writing-docs", "sentry", "posthog", "docker", "caprover"] {
            assert!(docs.pages.iter().any(|page| page.slug == slug), "missing option guide: {slug}");
        }
        let paths: HashSet<_> = docs.pages.iter().map(|page| page.path.as_str()).chain(["/docs"]).collect();
        for name in Content::iter() {
            let content = Content::get(&name).unwrap();
            let text = std::str::from_utf8(&content.data).unwrap();
            for event in Parser::new(text) {
                if let Event::Start(pulldown_cmark::Tag::Link { dest_url, .. }) = event {
                    let path = dest_url.split('#').next().unwrap();
                    if path.starts_with("/docs") {
                        assert!(paths.contains(path), "broken docs link in {name}: {path}");
                    }
                }
            }
        }
    }
    #[test]
    fn docs_sort_filter_drafts_and_render_markdown() {
        let docs = Docs::from_sources(vec![
            source("welcome", 0, false),
            source("second", 2, false),
            source("hidden", 0, true),
            source("first", 1, false),
        ])
        .unwrap();
        assert_eq!(docs.pages.iter().map(|p| p.slug.as_str()).collect::<Vec<_>>(), ["first", "second"]);
        let body = docs.pages[0].body.clone().into_string();
        assert!(body.contains("<h2>Start here</h2>"));
        assert!(body.contains("<strong>Rust</strong>"));
        assert!(!body.contains("<script>"));
    }
    #[test]
    fn markdown_tables_render_cells_and_keep_html_escaped() {
        let (_, mut text) = source("table", 1, false);
        text.push_str("\n| Method and path | Purpose |\n| --- | --- |\n| `GET /api/v1/me` | **Account** <script>alert(1)</script> |\n");
        let (_, page) = parse(&text).unwrap();
        let body = page.body.into_string();
        assert!(body.contains("<table><thead><tr><th>Method and path</th><th>Purpose</th></tr></thead>"));
        assert!(body.contains("<td><code>GET /api/v1/me</code></td>"));
        assert!(body.contains("<strong>Account</strong>"));
        assert!(body.contains("&lt;script&gt;"));
        assert!(!body.contains("<script>"));
    }

    #[test]
    fn invalid_content_and_duplicates_fail() {
        for slug in ["", "../escape", "UPPER", "two--dashes", "-leading", "trailing-", "page.md"] {
            assert!(Docs::from_sources(vec![source("welcome", 0, false), source(slug, 1, false)]).is_err());
        }
        assert!(
            Docs::from_sources(vec![source("welcome", 0, false), source("same", 1, false), source("same", 2, true)])
                .is_err()
        );
        assert!(parse("No front matter").is_err());
        let (_, valid) = source("page", 1, false);
        assert!(parse(&valid.replace("title = \"Getting started\"", "title = \"\"")).is_err());
        assert!(parse(&valid.replace("description =", "typo =")).is_err());
        assert!(parse(&valid.replace('\n', "\r\n")).is_ok());
        assert!(parse(&valid.replace("getting-started", "unknown-section")).is_err());
        assert!(Docs::from_sources(vec![source("page", 1, false)]).is_err());
        assert!(Docs::from_sources(vec![source("welcome", 0, true)]).is_err());
    }

    #[test]
    fn sections_sort_before_page_order_and_slug() {
        let section_source = |slug, order, section| {
            let (name, text) = source(slug, order, false);
            (name, text.replace("section = \"getting-started\"", &format!("section = \"{section}\"")))
        };
        let docs = Docs::from_sources(vec![
            source("welcome", 0, false),
            section_source("cli", 0, "developer-tools"),
            section_source("hosting", 0, "deployment"),
            section_source("sentry", 0, "features"),
            section_source("posthog", 0, "features"),
            source("start", 99, false),
        ])
        .unwrap();
        assert_eq!(
            docs.pages.iter().map(|page| page.slug.as_str()).collect::<Vec<_>>(),
            ["start", "posthog", "sentry", "hosting", "cli"]
        );
    }
}
