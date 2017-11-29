" vim match-up - matchit replacement and more
"
" Maintainer: Andy Massimino
" Email:      a@normed.space
"

let s:save_cpo = &cpo
set cpo&vim

function! matchup#motion#init_module() " {{{1
  if !g:matchup_motion_enabled | return | endif

  " utility maps to avoid conflict with "normal" command
  nnoremap <sid>(v) v
  nnoremap <sid>(V) V
  " c-v

  nnoremap <silent><expr> <sid>(wise)
        \ empty(g:v_motion_force) ? 'v' : g:v_motion_force

  " jump between matching pairs
  " TODO can % be made vi compatible wrt yank (:h quote_number)?

  " the basic motions % and g%
  nnoremap <silent> <plug>(matchup-%)
        \ :<c-u>call matchup#motion#find_matching_pair(0, 1)<cr>
  nnoremap <silent> <plug>(matchup-g%)
        \ :<c-u>call matchup#motion#find_matching_pair(0, 0)<cr>

  " visual and operator-pending
  xnoremap <silent> <sid>(matchup-%)
        \ :<c-u>call matchup#motion#find_matching_pair(1, 1)<cr>
  xmap     <silent> <plug>(matchup-%) <sid>(matchup-%)
  onoremap <plug>(matchup-%)
        \ :<c-u>call <sid>oper("normal \<sid>(wise)"
        \ . (v:count > 0 ? v:count : '') . "\<sid>(matchup-%)")<cr>

  xnoremap <silent> <sid>(matchup-g%)
        \ :<c-u>call matchup#motion#find_matching_pair(1, 0)<cr>
  xmap     <silent> <plug>(matchup-g%) <sid>(matchup-g%)
  onoremap <plug>(matchup-g%)
        \ :<c-u>call <sid>oper("normal \<sid>(wise)"
        \ . (v:count > 0 ? v:count : '') . "\<sid>(matchup-g%)")<cr>

  " ]% and [%
  nnoremap <silent> <plug>(matchup-]%)
        \ :<c-u>call matchup#motion#find_unmatched(0, 1)<cr>
  nnoremap <silent> <plug>(matchup-[%)
        \ :<c-u>call matchup#motion#find_unmatched(0, 0)<cr>
  xnoremap <silent> <sid>(matchup-]%)
        \ :<c-u>call matchup#motion#find_unmatched(1, 1)<cr>
  xnoremap <silent> <sid>(matchup-[%)
        \ :<c-u>call matchup#motion#find_unmatched(1, 0)<cr>
  xmap     <plug>(matchup-]%) <sid>(matchup-]%)
  xmap     <plug>(matchup-[%) <sid>(matchup-[%)

  onoremap <plug>(matchup-]%)
        \ :<c-u>call <sid>oper("normal \<sid>(wise)"
        \ . v:count1 . "\<sid>(matchup-]%)")<cr>
  onoremap <plug>(matchup-[%)
        \ :<c-u>call <sid>oper("normal \<sid>(wise)"
        \ . v:count1 . "\<sid>(matchup-[%)")<cr>

  " jump inside z%
  nnoremap <silent> <plug>(matchup-z%)
        \ :<c-u>call matchup#motion#jump_inside(0)<cr>
  xnoremap <silent> <sid>(matchup-z%)
        \ :<c-u>call matchup#motion#jump_inside(1)<cr>
  xmap     <silent> <plug>(matchup-z%) <sid>(matchup-z%)

  onoremap <silent> <plug>(matchup-z%)
        \ :<c-u>call <sid>oper("normal \<sid>(wise)"
        \ . v:count1 . "\<sid>(matchup-z%)")<cr>
endfunction

function! s:oper(expr)
  let s:v_operator = v:operator
  execute a:expr
  unlet s:v_operator
endfunction

" }}}1

function! matchup#motion#find_matching_pair(visual, down) " {{{1
  let [l:count, l:count1] = [v:count, v:count1]

  let l:is_oper = !empty(get(s:, 'v_operator', ''))

  if a:visual && !l:is_oper
    normal! gv
  endif

  if a:down && l:count > g:matchup_motion_override_Npercent
    " TODO: dv50% does not work properly
    if a:visual && l:is_oper
      normal! V
    endif
    exe 'normal!' l:count.'%'
    return
  endif

  " disable the timeout
  call matchup#perf#timeout_start(0)

  " get a delim where the cursor is
  let l:delim = matchup#delim#get_current('all', 'both_all')
  if empty(l:delim)
    " otherwise search forward
    let l:delim = matchup#delim#get_next('all', 'both_all')
    if empty(l:delim) | return | endif
  endif

  " loop count number of times
  for l:dummy in range(l:count1)
    let l:matches = matchup#delim#get_matching(l:delim, 1)
    if len(l:matches) <= 1 | return | endif
    if !has_key(l:delim, 'links') | return | endif
    let l:delim = get(l:delim.links, a:down ? 'next' : 'prev', {})
    if empty(l:delim) | return | endif
  endfor

  if a:visual && l:is_oper
    normal! gv
  endif

  let l:exclusive = l:is_oper && (g:v_motion_force ==# 'v')
  let l:forward = ((a:down && l:delim.side !=# 'open')
        \ || l:delim.side ==# 'close')

  " go to the end of the delimiter, if necessary
  let l:column = l:delim.cnum
  if g:matchup_motion_cursor_end && !l:is_oper && l:forward
    let l:column = matchup#delim#jump_target(l:delim)
  endif

  let l:start_pos = matchup#pos#get_cursor()

  normal! m`

  " column position of last character in match
  let l:eom = l:delim.cnum + matchup#delim#end_offset(l:delim)

  if l:is_oper && l:forward
    let l:column = l:exclusive ? (l:column - 1) : l:eom
  endif

  if l:is_oper && l:exclusive
        \ && matchup#pos#smaller(l:delim, l:start_pos)
    normal! o
    call matchup#pos#set_cursor(matchup#pos#prev(l:start_pos))
    normal! o
  endif

  " special handling for d%
  let [l:start_lnum, l:start_cnum] = l:start_pos[1:2]
  if get(s:, 'v_operator', '') ==# 'd' && l:start_lnum != l:delim.lnum
        \ && g:v_motion_force ==# ''
    let l:tl = [l:start_lnum, l:start_cnum]
    let [l:tl, l:br, l:swap] = l:tl[0] <= l:delim.lnum
          \ ? [l:tl, [l:delim.lnum, l:eom], 0]
          \ : [[l:delim.lnum, l:delim.cnum], l:tl, 1]

    if getline(l:tl[0]) =~# '^[ \t]*\%'.l:tl[1].'c'
          \ && getline(l:br[0]) =~# '\%'.(l:br[1]+1).'c[ \t]*$'
      if l:swap
        normal! o
        call matchup#pos#set_cursor(l:br[0], strlen(getline(l:br[0]))+1)
        normal! o
        let l:column = 1
      else
        normal! o
        call matchup#pos#set_cursor(l:tl[0], 1)
        normal! o
        let l:column = strlen(getline(l:br[0]))+1
      endif
    endif
  endif

  call matchup#pos#set_cursor(l:delim.lnum, l:column)
endfunction

" }}}1
function! matchup#motion#find_unmatched(visual, down) " {{{1
  call matchup#perf#tic('motion#find_unmatched')

  let l:count = v:count1
  let l:exclusive = !empty(get(s:, 'v_operator', ''))
        \ && g:v_motion_force !=# 'v' && g:v_motion_force !=# "\<c-v>"

  if a:visual
    normal! gv
  endif

  " disable the timeout
  call matchup#perf#timeout_start(0)

  for l:second_try in range(2)
    let [l:open, l:close] = matchup#delim#get_surrounding('delim_all',
          \ l:second_try ? l:count : 1)

    if empty(l:open) || empty(l:close)
      call matchup#perf#toc('motion#find_unmatched', 'fail'.l:second_try)
      return
    endif

    let l:delim = a:down ? l:close : l:open

    let l:save_pos = matchup#pos#get_cursor()
    let l:new_pos = [l:delim.lnum, l:delim.cnum]

    " this is an exclusive motion, ]%
    if l:delim.side ==# 'close'
      if l:exclusive
        let l:new_pos[1] -= 1
      else
        let l:new_pos[1] += matchup#delim#end_offset(l:delim)
      endif
    endif

    " if the cursor didn't move, increment count
    if matchup#pos#equal(l:save_pos, l:new_pos)
      let l:count += 1
    endif

    if l:count <= 1
      break
    endif
  endfor

  " this is an exclusive motion, [%
  if !a:down && l:exclusive
    normal! o
    call matchup#pos#set_cursor(matchup#pos#prev(
          \ matchup#pos#get_cursor()))
    normal! o
  endif

  normal! m`
  call matchup#pos#set_cursor(l:new_pos)

  call matchup#perf#toc('motion#find_unmatched', 'done')
endfunction

" }}}1
function! matchup#motion#jump_inside(visual) " {{{1
  let l:count = v:count1

  let l:save_pos = matchup#pos#get_cursor()

  if a:visual
    normal! gv
  endif

  for l:counter in range(l:count)
    if l:counter
      let l:delim = matchup#delim#get_next('all', 'open')
    else
      let l:delim = matchup#delim#get_current('all', 'open')
      if empty(l:delim)
        let l:delim = matchup#delim#get_next('all', 'open')
      endif
    endif
    if empty(l:delim)
      call matchup#pos#set_cursor(l:save_pos)
      return
    endif

    let l:new_pos = [l:delim.lnum, l:delim.cnum]
    let l:new_pos[1] += matchup#delim#end_offset(l:delim)
    call matchup#pos#set_cursor(matchup#pos#next(l:new_pos))
  endfor

  call matchup#pos#set_cursor(l:save_pos)

  " convert to [~, lnum, cnum, ~] format
  let l:new_pos = matchup#pos#next(l:new_pos)

  " this is an exclusive motion except when dealing with whitespace
  if !empty(get(s:, 'v_operator', ''))
        \ && g:v_motion_force !=# 'v' && g:v_motion_force !=# "\<c-v>"
    while matchup#util#in_whitespace(l:new_pos[1], l:new_pos[2])
      let l:new_pos = matchup#pos#next(l:new_pos)
    endwhile
    let l:new_pos = matchup#pos#prev(l:new_pos)
  endif

  normal! m`
  call matchup#pos#set_cursor(l:new_pos)
endfunction

" }}}1

let &cpo = s:save_cpo

" vim: fdm=marker sw=2

