import starlight from "@astrojs/starlight";
import a11yEmoji from "@fec/remark-a11y-emoji";
import { defineConfig } from "astro/config";
import starlightAnnouncement from "starlight-announcement";
import starlightHeadingBadges from "starlight-heading-badges";
import starlightLinksValidator from "starlight-links-validator";
import starlightLlmsTxt from "starlight-llms-txt";
import starlightSidebarTopics from "starlight-sidebar-topics";

const sidebar = [
	{
		label: "Start Here",
		items: [
			{ label: "What is Gluegun?", slug: "introduction" },
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
	{
		label: "Reference",
		items: [
			{
				label: "API Reference (HexDocs)",
				link: "https://hexdocs.pm/gluegun/",
			},
		],
	},
];

// https://astro.build/config
export default defineConfig({
	site: "https://gluegun.tylerbutler.com",
	prefetch: {
		defaultStrategy: "hover",
		prefetchAll: true,
	},
	integrations: [
		starlight({
			title: "Gluegun",
			editLink: {
				baseUrl: "https://github.com/tylerbutler/gluegun/edit/main/website/",
			},
			description: "Typed Gleam wrapper for the Erlang Gun HTTP client.",
			lastUpdated: true,
			logo: {
				dark: "./src/assets/gluegun-dark.png",
				light: "./src/assets/gluegun-light.png",
				alt: "Gluegun logo",
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
			plugins: [
				starlightLlmsTxt(),
				starlightHeadingBadges(),
				starlightSidebarTopics([
					{
						label: "Start Here",
						link: "/introduction/",
						items: [sidebar[0]],
					},
					{
						label: "Guides",
						link: "/guides/basic-requests/",
						items: [sidebar[1]],
					},
					{
						label: "Advanced",
						link: "/advanced/message-flow/",
						items: [sidebar[2]],
					},
					{
						label: "Reference",
						link: "https://hexdocs.pm/gluegun/",
						items: [sidebar[3]],
					},
				]),
				starlightAnnouncement({
					announcements: [
						{
							id: "welcome",
							content: "Welcome to the Gluegun documentation!",
							variant: "tip",
						},
					],
				}),
				starlightLinksValidator(),
			],
			social: [
				{
					icon: "github",
					label: "GitHub",
					href: "https://github.com/tylerbutler/gluegun",
				},
			],
		}),
	],
	markdown: {
		smartypants: false,
		remarkPlugins: [a11yEmoji],
	},
});
