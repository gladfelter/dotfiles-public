" --- BASIC SETTINGS ---
set nocompatible            " Use Vim defaults instead of Vi
set number                  " Show line number
set relativenumber          " Great for jumping lines (e.g., 5j)
set showcmd                 " Show incomplete command
set nocursorline            " Highlight current line
set wildmenu                " Visual autocomplete for command menu
set showmatch               " Highlight matching bracket
set incsearch               " Search as you type
set hlsearch                " Highlight search result
set clipboard=unnamedplus   " Link to Windows/System clipboard
set ignorecase              " Make searching case-insensitive
set smartcase               " ...UNLESS the search contains a capital letter
set fixendofline            " Automatically add a newline to the end of the file on save
set endofline               " Use the standard EOF newline

" --- INDENTATION (Tabstop of 2) ---
set tabstop=2               " Width of a hard tab
set shiftwidth=2            " Width of auto-indent
set softtabstop=2           " Fine-tune tabs to feel like space
set expandtab               " Turn tabs into space
set autoindent
set smartindent

" --- INTERFACE FIXES ---
set mouse=a                 " Enable mouse support in all mode
" Change cursor to block on startup (2) and bar on exit (6)
let &t_ti .= "\e[2 q"
let &t_te .= "\e[6 q"

" --- CUSTOM MAPPINGS ---
" Use space as leader key (common at work setups)
let mapleader = " "

" Fast escape
inoremap jj <Esc>

" Clear search highlights with Leader + Enter
nnoremap <Leader><CR> :noh<CR>

" Columnar select mode (visual block)
nnoremap <Leader>v <C-v>

" Smart Paste: If the clipboard has a newline, paste linewise
function! SmartPaste()
  if getreg('+') =~ '\n'
    return ":put +\<CR>"
  else
    return "p"
  endif
endfunction

nnoremap <expr> p SmartPaste()

" Ensure Vim recognizes both Unix and DOS format
set fileformats=unix,dos

" =============================================================================
" 1. PRE-PLUGIN SETTINGS (Global Toggles)
" =============================================================================
" These MUST be set before the plugins load to take effect
let g:vim_markdown_frontmatter = 1
" Disable concealing in JSON file
let g:vim_json_syntax_conceal = 0
" Disable concealing in Markdown (often used for links and bold text)
let g:vim_markdown_conceal = 0
let g:vim_markdown_conceal_code_blocks = 0

" --- PLUGINS ---
call plug#begin('~/.vim/plugged')

" The Essential
Plug 'tpope/vim-sensible'          " Better defaults everyone agrees on
Plug 'vim-airline/vim-airline'     " A much better status bar at the bottom
Plug 'preservim/nerdtree'          " File explorer (use :NERDTreeToggle)

" Markdown & Frontmatter
Plug 'preservim/vim-markdown'      " Enhanced Markdown support
Plug 'elzr/vim-json'               " Better JSON highlighting

" Formatting & Linting (The 'formatter' you asked for)
Plug 'dense-analysis/ale'          " Asynchronous Linting/Formatting

" Project-specific formatting rule
Plug 'editorconfig/editorconfig-vim'

call plug#end()

" --- PLUGIN CONFIGURATION ---
" Configure ALE to format on save
let g:ale_fixers = {
\   'javascript': ['eslint'],
\   'json': ['jq'],
\   'markdown': ['prettier'],
\   'python': ['black'],
\}
let g:ale_fix_on_save = 1

" Global override: 0 = visible, 1/2 = hidden
set conceallevel=0

filetype plugin indent on
syntax on

" Final UI tweaks that need syntax to be on first
set background=dark

" --- CUSTOM OVERRIDES & AUTOMATION ---
augroup user_config
  autocmd!

  " 1. CLEANUP: Strip trailing whitespace AND Windows <CR> on save
  autocmd BufWritePre * keepjumps silent! %s/[[:space:]\r]\+$//e


  " 2. FILE DETECTION: Ensure correct filetype for Markdown and JSON
  autocmd BufRead,BufNewFile *.md set filetype=markdown
  autocmd BufRead,BufNewFile *.json set filetype=json

  " 3. MARKDOWN SPECIFICS: Indenting and readability
  autocmd FileType markdown setlocal wrap linebreak nolist
  autocmd FileType markdown setlocal autoindent expandtab tabstop=2 shiftwidth=2

  " 4. FRONTMATTER: Prevent indentation logic from breaking YAML header
  autocmd FileType markdown setlocal nosmartindent
augroup END
