// subset-font ships no types; declare the slice of its API this script uses.
declare module "subset-font" {
  interface SubsetFontOptions {
    targetFormat?: "sfnt" | "woff" | "woff2" | "truetype";
    preserveNameIds?: number[];
    variationAxes?: Record<string, number>;
    noLayoutClosure?: boolean;
  }

  export default function subsetFont(
    originalFont: Buffer,
    text: string,
    options?: SubsetFontOptions,
  ): Promise<Buffer>;
}
