// SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
// Copyright (c) 2026 the contributors to this fork.
//
//! Build graph for PCRE2 runtime loading.
//! Generates a dispatch from the selected target's translated headers without linking PCRE2.

const std = @import("std");

/// Prefix shared by the synchronization C binding and Zig declarations.
const sync_prefix = "pcre2_rt";

/// C-library externs kept direct, including optimized and fortified variants.
/// This is the union across supported target configurations.
const libc_noise =
    \\_Exit,_OSSwapInt32,_OSSwapInt64,___mb_cur_max,___mb_cur_max_func,__assert,__assert_fail,__builtin_alloca,
    \\__byte_swap_u16_variable,__byte_swap_u32_variable,__byte_swap_u64_variable,__ctype_get_mb_cur_max,__debugbreak,
    \\__doserrno,__fastfail,__mb_cur_max,__mingw_aligned_free,__mingw_aligned_malloc,__mingw_aligned_msize,
    \\__mingw_aligned_offset_malloc,__mingw_aligned_offset_realloc,__mingw_aligned_realloc,__mingw_get_crt_info,__mingw_strtod,
    \\__mingw_strtof,__mingw_strtold,__mingw_wcstod,__mingw_wcstof,__mingw_wcstold,__p___argc,__p___argv,__p___wargv,
    \\__p__amblksiz,__p__environ,__p__fmode,__p__osplatform,__p__osver,__p__pgmptr,__p__wenviron,__p__winmajor,__p__winminor,
    \\__p__winver,__p__wpgmptr,__prefetch,__qsort_r_compat,__strtod,__sys_errlist,__sys_nerr,_aligned_free,_aligned_malloc,
    \\_aligned_msize,_aligned_offset_malloc,_aligned_offset_realloc,_aligned_offset_recalloc,_aligned_realloc,
    \\_aligned_recalloc,_atodbl,_atodbl_l,_atof_l,_atoflt,_atoflt_l,_atoi64,_atoi64_l,_atoi_l,_atol_l,_atoldbl,_atoldbl_l,
    \\_beep,_byteswap_uint64,_byteswap_ulong,_byteswap_ushort,_dupenv_s,_ecvt,_ecvt_s,_environ,_errno,_exit,_expand,_fcvt,
    \\_fcvt_s,_fullpath,_gcvt,_gcvt_s,_get_amblksiz,_get_doserrno,_get_errno,_get_fmode,_get_heap_handle,
    \\_get_invalid_parameter_handler,_get_osplatform,_get_osver,_get_pgmptr,_get_purecall_handler,_get_sbh_threshold,
    \\_get_winmajor,_get_winminor,_get_winver,_get_wpgmptr,_heapadd,_heapchk,_heapmin,_heapset,_heapused,_heapwalk,_i64toa,
    \\_i64toa_s,_i64tow,_i64tow_s,_itoa,_itoa_s,_itow,_itow_s,_lrotl,_lrotr,_ltoa,_ltoa_s,_ltow,_ltow_s,_makepath,_makepath_s,
    \\_mb_cur_max_l,_mbctype,_mblen_l,_mbstowcs_l,_mbstowcs_s_l,_mbstrlen,_mbstrlen_l,_mbstrnlen,_mbstrnlen_l,_mbtowc_l,_msize,
    \\_onexit,_pctype,_putenv,_putenv_s,_recalloc,_resetstkoflw,_rotl,_rotl64,_rotr,_rotr64,_searchenv,_searchenv_s,
    \\_set_abort_behavior,_set_amblksiz,_set_doserrno,_set_errno,_set_error_mode,_set_fmode,_set_invalid_parameter_handler,
    \\_set_malloc_crt_max_wait,_set_purecall_handler,_set_sbh_threshold,_seterrormode,_sleep,_splitpath,_splitpath_s,_strtod_l,
    \\_strtof_l,_strtoi64,_strtoi64_l,_strtol_l,_strtoui64,_strtoui64_l,_strtoul_l,_swab,_ui64toa,_ui64toa_s,_ui64tow,
    \\_ui64tow_s,_ultoa,_ultoa_s,_ultow,_ultow_s,_wcstod_l,_wcstof_l,_wcstoi64,_wcstoi64_l,_wcstol_l,_wcstombs_l,_wcstombs_s_l,
    \\_wcstoui64,_wcstoui64_l,_wcstoul_l,_wctomb_l,_wctomb_s_l,_wdupenv_s,_wfullpath,_wgetenv,_wgetenv_s,_wmakepath,
    \\_wmakepath_s,_wperror,_wputenv,_wputenv_s,_wsearchenv,_wsearchenv_s,_wsplitpath,_wsplitpath_s,_wsystem,_wtof,_wtof_l,
    \\_wtoi,_wtoi64,_wtoi64_l,_wtoi_l,_wtol,_wtol_l,a64l,abort,abort2,abort_handler_s,abs,aligned_alloc,alloca,arc4random,
    \\arc4random_addrandom,arc4random_buf,arc4random_stir,arc4random_uniform,at_quick_exit,atexit,atof,atoi,atol,atoll,bsearch,
    \\bsearch_s,bswap16,bswap32,bswap64,btowc,calloc,calloc_conceal,cfree,cgetcap,cgetclose,cgetent,cgetfirst,cgetmatch,
    \\cgetnext,cgetnum,cgetset,cgetstr,cgetusedb,cgetustr,clearenv,clearerr,csetexpandtc,daemon,daemonfd,dehumanize_number,
    \\devname,devname_r,div,drand48,drand48_r,ecvt,ecvt_r,environ,erand48,erand48_r,exit,fcvt,fcvt_r,fdevname,fdevname_r,free,
    \\freezero,ftruncate,fwprintf,fwscanf,gcvt,getbsize,getdevmajor,getenv,getenv_r,getenv_s,getiopolicy_np,getloadavg,
    \\getpagesize,getpriority,getprogname,getrandom,getrlimit,getrusage,getsubopt,grantpt,heapsort,hmac,htonl,htons,
    \\humanize_number,ignore_handler_s,imaxabs,imaxdiv,imaxdiv_t,initstate,initstate_r,iswalnum,iswalpha,iswblank,iswcntrl,
    \\iswctype,iswdigit,iswgraph,iswlower,iswprint,iswpunct,iswspace,iswupper,iswxdigit,itoa,jrand48,jrand48_r,l64a,l64a_r,
    \\labs,lcong48,lcong48_deterministic,lcong48_r,ldiv,llabs,lldiv,lltoa,lltow,lrand48,lrand48_r,lseek,ltoa,mallinfo,
    \\mallinfo2,malloc,malloc_conceal,malloc_conf,malloc_message,malloc_size,malloc_trim,malloc_type_aligned_alloc,
    \\malloc_type_calloc,malloc_type_free,malloc_type_malloc,malloc_type_posix_memalign,malloc_type_realloc,malloc_type_valloc,
    \\malloc_type_zone_calloc,malloc_type_zone_free,malloc_type_zone_malloc,malloc_type_zone_memalign,malloc_type_zone_realloc,
    \\malloc_type_zone_valloc,malloc_usable_size,malloc_zone_apis_available,malloc_zone_from_ptr,
    \\malloc_zone_mallocable_size_for_ptr,malloc_zone_named,malloc_zone_pressure_relief,mblen,mblen_l,mbrlen,mbrtowc,mbsinit,
    \\mbsrtowcs,mbstowcs,mbstowcs_l,mbstowcs_s,mbtowc,mbtowc_l,memalign,memalignment,memccpy,memchr,memcmp,memcpy,memmove,
    \\mempcpy,memset,mergesort,mi_vector_hash,mkdtemp,mkdtemps,mkostemp,mkostemps,mkostempsat,mkstemp,mkstemps,mktemp,mrand48,
    \\mrand48_r,nrand48,nrand48_r,ntohl,ntohs,on_exit,onexit,perror,posix_memalign,posix_openpt,pselect,psort,psort_r,ptsname,
    \\ptsname_r,putenv,qabs,qdiv,qecvt,qecvt_r,qfcvt,qfcvt_r,qgcvt,qsort,qsort_r,qsort_s,quick_exit,radixsort,rand,rand_r,
    \\random,random_r,realloc,reallocarr,reallocarray,reallocf,realpath,recallocarray,rpmatch,secure_getenv,seed48,
    \\seed48_deterministic,seed48_r,select,set_constraint_handler_s,setenv,setiopolicy_np,setkey,setpriority,setproctitle,
    \\setprogname,setrlimit,setstate,setstate_r,shquote,shquotev,signal,sradixsort,srand,srand48,srand48_deterministic,
    \\srand48_r,srand_deterministic,sranddev,srandom,srandom_deterministic,srandom_r,srandomdev,stpcpy,strcasecmp,strcasecmp_l,
    \\strcat,strchr,strcmp,strcoll,strcpy,strcspn,strdup,strerror,strerror_l,strerror_r,strfromd,strfromf,strfroml,strlen,
    \\strncasecmp,strncasecmp_l,strncat,strncmp,strncpy,strndup,strnlen,strpbrk,strrchr,strsignal,strspn,strstr,strsuftoll,
    \\strsuftollx,strtod,strtod_l,strtof,strtof_l,strtoi,strtoi_l,strtoimax,strtoimax_l,strtok_r,strtol,strtol_l,strtold,
    \\strtold_l,strtoll,strtoll_l,strtonum,strtoq,strtoq_l,strtou,strtou_l,strtoul,strtoul_l,strtoull,strtoull_l,strtoumax,
    \\strtoumax_l,strtouq,strtouq_l,strxfrm,suboptarg,swab,swprintf,swscanf,system,truncate,ttyslot,ulltoa,ulltow,ultoa,
    \\unlockpt,unsetenv,valloc,vfork,vfwprintf,vfwscanf,vswprintf,vswscanf,vwprintf,vwscanf,wait,wait3,wait4,waitid,waitpid,
    \\wcrtomb,wcscasecmp,wcscasecmp_l,wcscat,wcschr,wcscmp,wcscoll,wcscpy,wcscspn,wcsdup,wcsftime,wcslen,wcsncasecmp,
    \\wcsncasecmp_l,wcsncat,wcsncmp,wcsncpy,wcsnlen,wcsrtombs,wcsspn,wcsstr,wcstod,wcstof,wcstoimax,wcstoimax_l,wcstok,wcstol,
    \\wcstold,wcstoll,wcstombs,wcstombs_l,wcstombs_s,wcstoul,wcstoull,wcstoumax,wcstoumax_l,wcsxfrm,wctob,wctomb,wctomb_l,
    \\wctomb_s,wctype,wmemchr,wmemcmp,wmemcpy,wmemmove,wmemset,wmemset_ex,wprintf,wscanf,wtoll,
    \\__fdelt_chk,__fdelt_warn,__mbstowcs_alias,__mbstowcs_chk,__mbstowcs_chk_warn,
    \\__mbstowcs_nulldst,__ptsname_r_alias,__ptsname_r_chk,__ptsname_r_chk_warn,__realpath_alias,
    \\__realpath_chk,__realpath_chk_warn,__wcstombs_alias,__wcstombs_chk,__wcstombs_chk_warn,__wctomb_alias,
    \\__wctomb_chk
;

/// Provider-optional exports; none, because this descriptor requires every routed symbol.
const provider_optional = "";

/// Provider exports excluded from lookup; none for PCRE2.
const provider_excluded = "";

/// Create the loader core module for linked builds.
pub fn createCoreModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("runtime/loader.zig"),
        .target = target,
        .optimize = optimize,
        // Unix dynamic loading uses libc.
        .link_libc = true,
    });
}

/// Create the runtime-loaded C module from this target's translated output.
/// This graph does not link the native PCRE2 library.
pub fn createModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const core = createCoreModule(b, target, optimize);

    const library = b.createModule(.{
        .root_source_file = b.path("runtime/library.zig"),
        .target = target,
        .optimize = optimize,
    });
    library.addImport("rt", core);

    return createDispatchModule(b, translate, target, optimize, core, library);
}

/// Generated native translation and runtime dispatch source paths.
const GeneratedSources = struct {
    native: std.Build.LazyPath,
    dispatch: std.Build.LazyPath,
};

fn createDispatchModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: *std.Build.Module,
    library: *std.Build.Module,
) *std.Build.Module {
    const sources = generateDispatch(b, translate, target);

    const dispatch = b.createModule(.{
        .root_source_file = sources.dispatch,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dispatch.addImport("rt", core);
    dispatch.addImport("library", library);

    // Re-export translated declarations to preserve their nominal types.
    const native = b.createModule(.{
        .root_source_file = sources.native,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    native.addImport("c_routed", dispatch);
    dispatch.addImport("c_native", native);
    dispatch.addCSourceFiles(.{
        .files = &.{"runtime/sync.c"},
        .flags = &.{b.fmt("-DRT_SYNC_PREFIX={s}", .{sync_prefix})},
        .language = .c,
    });
    return dispatch;
}

/// Generate dispatch files from this target's translated output.
fn generateDispatch(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
) GeneratedSources {
    const generator = b.addExecutable(.{
        .name = b.fmt("pcre2-runtime-generate-{s}", .{
            target.result.zigTriple(b.allocator) catch @panic("unspellable target"),
        }),
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/generate.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    const run = b.addRunArtifact(generator);
    run.addArg("--library");
    run.addArg("pcre2");
    run.addArg("--translate");
    run.addFileArg(translate.getOutput());
    if (libc_noise.len != 0) {
        run.addArg("--noise");
        run.addArg(libc_noise);
    }
    if (provider_optional.len != 0) {
        run.addArg("--optional");
        run.addArg(provider_optional);
    }
    if (provider_excluded.len != 0) {
        run.addArg("--exclude");
        run.addArg(provider_excluded);
    }
    run.addArg("--native-output");
    const native_source = run.addOutputFileArg("native.zig");
    run.addArg("--output");
    const dispatch_source = run.addOutputFileArg("dispatch.zig");
    return .{ .native = native_source, .dispatch = dispatch_source };
}
