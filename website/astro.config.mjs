import starlight from "@astrojs/starlight";
import a11yEmoji from "@fec/remark-a11y-emoji";
import { defineConfig } from "astro/config";
import starlightLinksValidator from "starlight-links-validator";
import starlightLlmsTxt from "starlight-llms-txt";

// https://astro.build/config
export default defineConfig({
	site: "https://gluegun.tylerbutler.com",
	prefetch: {
		defaultStrategy: "hover",
		prefetchAll: true,
	},
	integrations: [
		starlight({
			title: "gluegun",
			editLink: {
				baseUrl: "https://github.com/tylerbutler/gluegun/edit/main/website/",
			},
			description: "Typed Gleam wrapper for the Erlang Gun HTTP client.",
			lastUpdated: true,
			logo: {
				dark: "./src/assets/gluegun-dark.png",
				light: "./src/assets/gluegun-light.png",
				alt: "gluegun logo",
				// width: 48,
				// height: 48,
			},
			favicon: "./src/assets/gluegun-dark.png",
			customCss: [
				"@fontsource/metropolis/400.css",
				"@fontsource/metropolis/600.css",
				"./src/styles/fonts.css",
				"./src/styles/custom.css",
			],
			plugins: [starlightLlmsTxt(), starlightLinksValidator()],
			social: [
				{
					icon: "github",
					label: "GitHub",
					href: "https://github.com/tylerbutler/gluegun",
				},
			],
			sidebar: [
				{
					label: "Start Here",
					items: [
						{ label: "What is gluegun?", slug: "introduction" },
						{ label: "Installation", slug: "installation" },
						{ label: "Quick Start", slug: "quick-start" },
					],
				},
				{
					label: "Guides",
					items: [
						{ label: "Basic Requests", slug: "guides/basic-requests" },
						{ label: "Streaming", slug: "guides/streaming" },
						{ label: "WebSockets", slug: "guides/websockets" },
						{ label: "HTTP/2", slug: "guides/http2" },
					],
				},
				{
					label: "Advanced",
					items: [
						{ label: "Message Flow", slug: "advanced/message-flow" },
						{ label: "Error Handling", slug: "advanced/error-handling" },
						{ label: "Limitations", slug: "advanced/limitations" },
						{ label: "Troubleshooting", slug: "advanced/troubleshooting" },
					],
				},
			],
		}),
	],
	markdown: {
		smartypants: false,
		remarkPlugins: [a11yEmoji],
	},
});
