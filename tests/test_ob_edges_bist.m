function test_ob_edges_bist ()
  cleanup = ob_test_setup ();
  [passed,total] = test (mfilename("fullpath"), "quiet");
  assert (total > 0 && passed == total);
  fprintf ("test_ob_edges_bist: %d/%d passed\n", passed, total);
endfunction

%!test
%! raw=[9 5;2 7;8 5;1 5;4 7];
%! assert(ob_edges(struct('edges',raw)),[9 1 5 1;2 1 7 1;8 1 5 2;1 1 5 3;4 1 7 2]);
%! assert(ob_edges(struct('edges',zeros(0,2))),zeros(0,4));

%!test
%! previous=rng();
%! unwind_protect
%!   rng(319,'twister');
%!   for n=0:80
%!     raw=randi(17,n,2); expected=zeros(n,4);
%!     for k=1:n,expected(k,:)=[raw(k,1),1,raw(k,2),1+sum(raw(1:k-1,2)==raw(k,2))];endfor
%!     assert(ob_edges(struct('edges',raw)),expected);
%!   endfor
%! unwind_protect_cleanup
%!   rng(previous);
%! end_unwind_protect

%!test
%! base=uint64(2)^53; raw=[base+1 base+1;base+2 base+3;base+3 base+1];
%! expected=zeros(3,4);
%! for k=1:3,expected(k,:)=[raw(k,1),1,raw(k,2),1+sum(raw(1:k-1,2)==raw(k,2))];endfor
%! actual=ob_edges(struct('edges',raw));assert(isa(actual,'double'));assert(actual,expected);
%! raw=single([1 2;1 2]);actual=ob_edges(struct('edges',raw));
%! assert(isa(actual,'double'));assert(actual,[1 1 2 1;1 1 2 2]);

%!test
%! raw=uint64([1 1 2 1]);assert(isequal(ob_edges(struct('edges',raw)),raw));
%! fail("ob_edges(struct('edges',[1 0]))",'valid block indices');
