# difft-pr

A command-line tool that enhances GitHub pull request reviews by displaying diffs using [Difftastic](https://difftastic.wilfred.me.uk/), a structural diff tool that understands syntax.

## AI slop warning

This tool was created with the help of AI.

## Features

- View GitHub pull request diffs with syntax-aware highlighting
- Works with both local repositories and remote GitHub repositories
- Supports dark and light terminal backgrounds
- Provides clear error messages and dependency checks
- Works with any GitHub repository you have access to

## Prerequisites

- [GitHub CLI (gh)](https://cli.github.com) - Must be installed and authenticated
- [Difftastic (difft)](https://difftastic.wilfred.me.uk/) - For syntax-aware diff viewing
- [coreutils](https://www.gnu.org/software/coreutils/) - For the `csplit` utility

### Installation of Dependencies

## Usage

### Basic Usage

View a pull request in the current repository:

```bash
difft-pr 123
```

### Options

```
Options:
    -h, --help              Show this help message
    -v, --version          Show version information
    -b, --background       Set background color (dark/light) [default: dark]
    -r, --repo OWNER/REPO  Specify the GitHub repository (if not in repo directory)
```

### Examples

View a PR in a specific repository:

```bash
difft-pr -r owner/repo 123
```

Use with light terminal background:

```bash
difft-pr -b light 123
```

### Environment Variables

- `DIFFT_DISPLAY`: Set to `inline` for inline diff view instead of side-by-side
- `DIFFT_BACKGROUND`: Can be set to `dark` or `light` (alternative to -b flag)

## Troubleshooting

1. If you get "not authenticated" errors:

   ```bash
   gh auth login
   ```

2. If diffs don't appear:

   - Ensure you have access to the repository
   - Check if the PR number is correct
   - Verify you're in a git repository or using the -r option

3. If colors don't look right:
   - Try switching the background setting: `-b light` or `-b dark`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

