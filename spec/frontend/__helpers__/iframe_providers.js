export const YOUTUBE_SANDBOX =
  'allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox';

export const FIGMA_SANDBOX = 'allow-scripts allow-same-origin allow-popups';

export const iframeProviders = () => ({
  youtube: {
    name: 'YouTube',
    match_hosts: ['www.youtube.com', 'youtu.be'],
    src_origin: 'https://www.youtube.com',
    sandbox: YOUTUBE_SANDBOX,
    require_activation: false,
  },
  figma: {
    name: 'Figma',
    match_hosts: ['embed.figma.com', 'www.figma.com'],
    src_origin: 'https://embed.figma.com',
    sandbox: FIGMA_SANDBOX,
    require_activation: true,
  },
});
