import { $, argv, chalk, fs, glob, path } from 'zx'
import MarkdownIt from 'markdown-it'
import os from 'os'

// Files excluded from --all batch processing
const EXCLUDE = [
  'docs/source-bundle.md',  // generated source dump, not a readable document
]

if (argv.h || argv.help) {
  console.log(`
  Usage: md-to-pdf.sh <input.md> [output.pdf]
         md-to-pdf.sh --all

  Converts Markdown files to PDF using VS Code preview styles.
  PDFs are written alongside their source .md files.

  Arguments:
    input.md      Path to the source Markdown file
    output.pdf    Path for the generated PDF (defaults to same location as input)

  Options:
    --all         Convert every .md file in the current directory tree
    -h, --help    Print this help
  `)
  process.exit(0)
}

// Styles are bundled with the skill; SKILL_DIR is set by the md-to-pdf.sh wrapper
const skillDir   = process.env.SKILL_DIR ?? path.resolve(import.meta.dirname, '..')
const stylesDir  = path.join(skillDir, 'assets', 'styles')
const markdownCss  = await fs.readFile(`${stylesDir}/markdown.css`, 'utf8')
const highlightCss = await fs.readFile(`${stylesDir}/tomorrow.css`, 'utf8')
const pdfCss       = await fs.readFile(`${stylesDir}/markdown-pdf.css`, 'utf8')
const md           = new MarkdownIt({ html: true, linkify: true, typographer: true })

// Generate a GitHub-compatible anchor id from a heading's text content
function toAnchor(text: string): string {
  return text
    .toLowerCase()
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/[^\w\s-]/g, '')
    .replace(/ /g, '-')
    .replace(/^-+|-+$/g, '')
}

// Add id attributes to heading elements so internal PDF links work
function addHeadingIds(html: string): string {
  return html.replace(/<(h[1-6])>(.*?)<\/\1>/gi, (_match, tag, inner) => {
    const text = inner.replace(/<[^>]+>/g, '')
    return `<${tag} id="${toAnchor(text)}">${inner}</${tag}>`
  })
}

async function convert(inputPath: string, outputPath: string) {
  const tmpHtml = path.join(os.tmpdir(), path.basename(inputPath).replace(/\.md$/, '_tmp.html'))
  const body    = addHeadingIds(md.render(await fs.readFile(inputPath, 'utf8')))

  const html = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>${path.basename(inputPath)}</title>
<style>${markdownCss}</style>
<style>${highlightCss}</style>
<style>${pdfCss}</style>
</head>
<body class="vscode-body">
${body}
</body>
</html>`

  await fs.writeFile(tmpHtml, html)
  console.log(chalk.blue(`Generating: ${path.relative(process.cwd(), outputPath)}`))
  await $`python3 -c "import sys; from weasyprint import HTML; HTML(filename=sys.argv[1]).write_pdf(sys.argv[2])" ${tmpHtml} ${outputPath}`
  await fs.rm(tmpHtml)
  console.log(chalk.green(`  ✓ ${path.relative(process.cwd(), outputPath)}`))
}

if (argv.all) {
  // When invoked via the shell wrapper, the caller's cwd is passed via env var
  // so that --all globs from the agent's workspace, not from engine-dev.
  const scanDir = process.env.MD_TO_PDF_INVOKE_CWD ?? process.cwd()
  const files = await glob('**/*.md', {
    cwd: scanDir,
    ignore: ['node_modules/**', 'dist/**', 'tmp/**', ...EXCLUDE],
    absolute: true,
  })
  console.log(chalk.blue(`Converting ${files.length} Markdown files...`))
  for (const file of files.sort()) {
    const inputPath  = file  // already absolute (glob absolute: true)
    const outputPath = inputPath.replace(/\.md$/, '.pdf')
    await convert(inputPath, outputPath)
  }
  console.log(chalk.green(`\nDone. ${files.length} PDFs generated.`))
} else {
  const inputArg = argv._[0]
  if (!inputArg) {
    console.error(chalk.red('Error: No input file specified.'))
    console.log('Usage: md-to-pdf.sh <input.md> [output.pdf]  |  md-to-pdf.sh --all')
    process.exit(1)
  }
  const inputPath  = path.resolve(inputArg)
  const outputPath = argv._[1] ? path.resolve(argv._[1]) : inputPath.replace(/\.md$/, '.pdf')
  await convert(inputPath, outputPath)
}
