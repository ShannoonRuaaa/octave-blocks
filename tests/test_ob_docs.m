function test_ob_docs ()
  test_path_cleanup = ob_test_setup ();
  % Documentation lint, run from the repository found relative to this file
  % (no git needed):
  % - the project text files and every Markdown file under doc/ are valid
  %   UTF-8;
  % - relative Markdown links in README.md, CONTRIBUTING.md, doc/*.md and
  %   tests/README.md resolve to existing files or folders, with the same
  %   letter case (Windows would hide a case mismatch that breaks on Linux);
  % - doc/README.md links every other doc/*.md file.
  root = fileparts (fileparts (mfilename ('fullpath')));
  failures = {};

  docs = dir (fullfile (root, 'doc', '*.md'));
  doc_names = sort ({docs.name});
  markdown = [{'README.md', 'CONTRIBUTING.md'}, strcat('doc/', doc_names), {'tests/README.md'}];
  text_ext = {'.m', '.ps1', '.md', '.json', '.txt', '.c', '.h', '.yml', '.yaml'};
  text_files = [markdown, {'NEWS', 'DESCRIPTION', 'INDEX', 'LICENSE', 'NOTICE', 'COPYING', ...
                'ob_setup.m', 'Launch-Blocks.ps1', 'inst/PKG_ADD', 'inst/PKG_DEL'}, ...
                nested_markdown(root, 'doc'), files_below(root, 'inst', text_ext), ...
                files_below(root, 'tests', text_ext), files_below(root, 'tools', text_ext), ...
                files_below(root, '.github', text_ext), files_below(root, 'LICENSES', text_ext)];
  text_files = unique (text_files, 'stable');

  % (a) UTF-8.
  contents = containers.Map ();
  for k = 1:numel (text_files)
    name = text_files{k};
    [fid, message] = fopen (fullfile (root, name), 'rb');
    if (fid < 0)
      failures{end+1} = sprintf ('%s: cannot be read (%s)', name, message);
      continue;
    endif
    bytes = fread (fid, Inf, 'uint8')';
    fclose (fid);
    bad = utf8_error (bytes);
    if (bad)
      failures{end+1} = sprintf ('%s: invalid UTF-8 at byte %d (0x%02X)', name, bad, bytes(bad));
      bytes(bytes >= 128) = '?';        % regexp rejects invalid UTF-8 input
    endif
    contents(name) = char (bytes);
  endfor

  % (b) Relative links.
  links = 0;
  index_targets = {};
  for k = 1:numel (markdown)
    name = markdown{k};
    if (! isKey (contents, name)), continue; endif
    [targets, lines] = markdown_links (contents(name));
    from = fileparts (fullfile (root, name));
    for j = 1:numel (targets)
      target = targets{j};
      if (! isempty (regexp (target, '^[A-Za-z][A-Za-z0-9+.-]*:', 'once')))
        continue;                       % http:, https:, mailto: and other URIs
      endif
      relative = regexprep (target, '[#?].*$', '');
      if (isempty (relative)), continue; endif  % an anchor in the same file
      links += 1;
      problem = check_target (root, from, strrep (relative, '%20', ' '));
      if (! isempty (problem))
        failures{end+1} = sprintf ('%s:%d: link "%s" %s', name, lines(j), target, problem);
      endif
      if (strcmp (name, 'doc/README.md'))
        index_targets{end+1} = regexprep (relative, '^\./', '');
      endif
    endfor
  endfor

  % (c) The doc index.
  missing = setdiff (setdiff (doc_names, {'README.md'}), index_targets);
  for k = 1:numel (missing)
    failures{end+1} = sprintf ('doc/README.md: does not link doc/%s', missing{k});
  endfor

  if (! isempty (failures))
    error ('test_ob_docs: %d documentation failure(s):\n  %s', numel (failures), ...
           strjoin (failures, "\n  "));
  endif
  printf (['Octave Blocks documentation tests passed (%d UTF-8 files, %d relative links ' ...
           'in %d Markdown files, %d docs indexed)\n'], ...
          numel (text_files), links, numel (markdown), numel (doc_names) - 1);
endfunction

function names = nested_markdown (root, folder)
  % Markdown files in the subfolders of FOLDER (doc/LICENSES, doc/images and
  % any later subfolder); their other files are not checked.
  names = {};
  entries = dir (fullfile (root, folder));
  for k = 1:numel (entries)
    entry = entries(k);
    if (! entry.isdir || any (strcmp (entry.name, {'.', '..'}))), continue; endif
    names = [names, markdown_below(root, [folder '/' entry.name])];
  endfor
endfunction

function names = markdown_below (root, folder)
  names = {};
  entries = dir (fullfile (root, folder));
  for k = 1:numel (entries)
    entry = entries(k);
    if (any (strcmp (entry.name, {'.', '..'}))), continue; endif
    relative = [folder '/' entry.name];
    if (entry.isdir)
      names = [names, markdown_below(root, relative)];
    elseif (numel (entry.name) > 3 && strcmpi (entry.name(end-2:end), '.md'))
      names{end+1} = relative;
    endif
  endfor
endfunction

function names = files_below (root, folder, extensions)
  % Files under FOLDER with one of EXTENSIONS, skipping names that start with
  % a dot (., .. and ignored run output such as tests/.artifacts).
  names = {};
  entries = dir (fullfile (root, folder));
  for k = 1:numel (entries)
    entry = entries(k);
    if (entry.name(1) == '.'), continue; endif
    relative = [folder '/' entry.name];
    [~, ~, extension] = fileparts (entry.name);
    if (entry.isdir)
      names = [names, files_below(root, relative, extensions)];
    elseif (any (strcmpi (extension, extensions)))
      names{end+1} = relative;
    endif
  endfor
endfunction

function bad = utf8_error (bytes)
  % Index of the first byte that does not start or continue a well-formed
  % UTF-8 sequence (RFC 3629: no overlong forms, surrogates or values above
  % U+10FFFF), or 0. Only bytes >= 0x80 are visited.
  bad = 0;
  high = find (bytes >= 128);
  n = numel (bytes);
  k = 1;
  while (k <= numel (high))
    i = high(k);
    b = bytes(i);
    if (b >= 194 && b <= 223), count = 1; lo = 128; hi = 191;
    elseif (b == 224), count = 2; lo = 160; hi = 191;
    elseif ((b >= 225 && b <= 236) || b == 238 || b == 239), count = 2; lo = 128; hi = 191;
    elseif (b == 237), count = 2; lo = 128; hi = 159;
    elseif (b == 240), count = 3; lo = 144; hi = 191;
    elseif (b >= 241 && b <= 243), count = 3; lo = 128; hi = 191;
    elseif (b == 244), count = 3; lo = 128; hi = 143;
    else
      bad = i; return;
    endif
    if (i + count > n), bad = i; return; endif
    next = bytes(i+1:i+count);
    if (next(1) < lo || next(1) > hi || any (next(2:end) < 128 | next(2:end) > 191))
      bad = i; return;
    endif
    k += count + 1;        % the continuation bytes are the next entries of HIGH
  endwhile
endfunction

function [targets, lines] = markdown_links (text)
  % Inline link and image targets, [text](target "title"), and reference
  % definitions, [label]: target, outside fenced code blocks and code spans.
  % Link text may wrap onto the next line, so the text is matched as a whole.
  inline = '\[[^\]]*\]\([ \t]*<?([^)\s>]+)>?(?:[ \t]+["''][^"'']*["''])?[ \t]*\)';
  reference = '^[ \t]{0,3}\[[^\]]+\]:[ \t]*<?([^\s>]+)>?';
  rows = regexp (text, '\r?\n', 'split');
  fenced = false;
  for k = 1:numel (rows)
    if (! isempty (regexp (rows{k}, '^[ \t]{0,3}(```|~~~)', 'once')))
      fenced = ! fenced;
      rows{k} = '';
    elseif (fenced)
      rows{k} = '';
    else
      rows{k} = regexprep (rows{k}, '`[^`]*`', '');
    endif
  endfor
  text = strjoin (rows, "\n");
  [found, starts] = regexp (text, inline, 'tokens', 'start');
  [more, more_starts] = regexp (text, reference, 'tokens', 'start', 'lineanchors');
  found = [found, more];
  starts = [starts, more_starts];
  breaks = find (text == "\n");
  targets = cellfun (@(t) t{1}, found, 'uniformoutput', false);
  lines = arrayfun (@(s) 1 + sum (breaks < s), starts);
endfunction

function problem = check_target (root, from, relative)
  % '' when RELATIVE (to FROM, or to ROOT with a leading '/') names an
  % existing file or folder whose last component has the same letter case.
  problem = '';
  if (relative(1) == '/')
    full = fullfile (root, relative(2:end));
  else
    full = fullfile (from, relative);
  endif
  [~, err] = stat (full);
  if (err != 0)
    problem = 'does not resolve to an existing file';
    return;
  endif
  [folder, base, extension] = fileparts (regexprep (full, '[\\/]+$', ''));
  entries = dir (folder);
  if (! isempty (base) && ! any (strcmp ({entries.name}, [base extension])))
    problem = 'differs in letter case from the file on disk';
  endif
endfunction
