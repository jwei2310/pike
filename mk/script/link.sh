#
# Copyright (c) Brian Koropoff
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the MakeKit project nor the names of its
#       contributors may be used to endorse or promote products derived
#       from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS ``AS IS''
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS
# BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
# THE POSSIBILITY OF SUCH DAMAGE.
#

combine_libtool_flags()
{
    for _lib in ${COMBINED_LIBDEPS}
    do
        for _path in ${COMBINED_LDFLAGS} -L/usr/lib -L/lib
        do
            case "$_path" in
                "-L"*)
                    if [ -e "${_path#-L}/lib${_lib}.la" ]
                    then
                        unset dependency_libs
                        mk_safe_source "${_path#-L}/lib${_lib}.la" || mk_fail "could not read libtool archive"
                        for _dep in ${dependency_libs}
                        do
                            case "$_dep" in
                                "${MK_LIBDIR}"/*.la)
                                    _dep="${_dep##*/}"
                                    _dep="${_dep#lib}"
                                    _mk_contains "${_dep%.la}" ${COMBINED_LIBDEPS} ||
                                    COMBINED_LIBDEPS="${COMBINED_LIBDEPS} ${_dep%.la}" 
                                    ;;
                                "-l"*)
                                    _mk_contains "${_dep#-l}" ${COMBINED_LIBDEPS} ||
                                    COMBINED_LIBDEPS="${COMBINED_LIBDEPS} ${_dep#-l}"
                                    ;;
                                "-L${MK_LIBDIR}")
                                    continue
                                    ;;
                                "-L"*)
                                    _mk_contains "${_dep}" ${COMBINED_LDFLAGS} ||
                                    COMBINED_LDFLAGS="$COMBINED_LDFLAGS $_dep"
                                    ;;
                            esac
                        done
                        break
                    fi
                    ;;
            esac
        done
    done
}

create_libtool_archive()
{
    # Create a .la file that can be used by combine_libtool_flags
    # (Or, theoretically, the real libtool)
    {
        # This line must be of the form "Generated by.*libtool"
        # in order for libtool to like it
        echo "# Generated by MakeKit (libtool compatible)"

        if [ -n "$SONAME" ]
        then
            mk_quote "$SONAME"
            echo "dlname=$result"
        else
            result="${_object##*/}"
            result="${result%.la}${EXT}"
            mk_quote "$result"
            echo "dlname=$result"
        fi

        if [ -n "$STATIC_NAME" ]
        then
            mk_quote "$STATIC_NAME"
            echo "old_library=$result"
        fi

        if [ -n "$LINKS" ]
        then
            mk_unquote_list "$LINKS"
            mk_quote "$*"
        else
            result="${_object##*/}"
            result="${result%.la}${EXT}"
            mk_quote "$result"
        fi
        echo "library_names=$result"

        mk_quote "-L${RPATH_LIBDIR} $_LIBS"
        echo "dependency_libs=$result"

        echo "installed='yes'"

        result="${_object%/*}"
        result="${result#$MK_STAGE_DIR}"
        mk_quote "$result"
        echo "libdir=$result"
    } > "$_object" || mk_fail "could not write $_object"

    mk_run_or_fail touch "$_object"
}

do_link()
{
    _object="$1"
    shift 1
    
    if [ "${MK_SYSTEM%/*}" = "build" ]
    then
        LINK_LIBDIR="$MK_RUN_LIBDIR"
        RPATH_LIBDIR="$MK_ROOT_DIR/$MK_RUN_LIBDIR"
    else
        RPATH_LIBDIR="$MK_LIBDIR"
        mk_resolve_file "$MK_LIBDIR"
        LINK_LIBDIR="$result"
    fi

    COMBINED_LIBDEPS="$LIBDEPS"
    COMBINED_LDFLAGS="$MK_ISA_LDFLAGS $MK_LDFLAGS $LDFLAGS"
    COMBINED_LIBDIRS="$LIBDIRS"
    
    [ -d "$LINK_LIBDIR" -a -z "$CONFTEST" ] && COMBINED_LDFLAGS="$COMBINED_LDFLAGS -L${LINK_LIBDIR}"
    
    # SONAME
    if [ -n "$SONAME" ]
    then
        case "$MK_OS" in
            darwin)
                COMBINED_LDFLAGS="$COMBINED_LDFLAGS -install_name ${MK_LIBDIR}/${SONAME}"
                ;;
            hpux)
                COMBINED_LDFLAGS="$COMBINED_LDFLAGS -Wl,+h,${SONAME}"
                ;;
            aix)
                : # SONAMEs aren't encoded in libraries
                ;;
            *)
                COMBINED_LDFLAGS="$COMBINED_LDFLAGS -Wl,-h,$SONAME"
                ;;
        esac
    fi

    # Group suffix
    _gsuffix=".${MK_CANONICAL_SYSTEM%/*}.${MK_CANONICAL_SYSTEM#*/}.og"

    case "$COMPILER" in
        c)
            CPROG="$MK_CC"
            LD_STYLE="$MK_CC_LD_STYLE"
            COMBINED_LDFLAGS="$COMBINED_LDFLAGS $MK_ISA_CFLAGS $MK_CFLAGS $CFLAGS"
            ;;
        c++)
            CPROG="$MK_CXX"
            LD_STYLE="$MK_CXX_LD_STYLE"
            COMBINED_LDFLAGS="$COMBINED_LDFLAGS $MK_ISA_CXXFLAGS $MK_CXXFLAGS $CXXFLAGS"
            ;;
    esac

    case "${MK_OS}:${LD_STYLE}" in
        *:gnu)
            DLO_LINK="-shared"
            LIB_LINK="-shared"
            ;;
        solaris:native)
            DLO_LINK="-shared"
            LIB_LINK="-shared"
            
            if [ "$MODE" = "library" ]
            then
                COMBINED_LDFLAGS="$COMBINED_LDFLAGS -Wl,-z,defs -Wl,-z,text"
                COMBINED_LIBDEPS="$COMBINED_LIBDEPS c"
            fi

            # The solaris linker is anal retentive about implicit shared library dependencies,
            # so use available libtool .la files to add implicit dependencies to the link command
            combine_libtool_flags
            ;;
        darwin:native)
            DLO_LINK="-bundle"
            LIB_LINK="-dynamiclib"
            COMBINED_LDFLAGS="$COMBINED_LDFLAGS -Wl,-undefined -Wl,dynamic_lookup -Wl,-single_module -Wl,-arch_errors_fatal"
            ;;
        aix:native)
            DLO_LINK="-shared -Wl,-berok -Wl,-bnoentry"
            LIB_LINK="-shared -Wl,-bnoentry"
            COMBINED_LDFLAGS="$COMBINED_LDFLAGS -Wl,-brtl"
            
            # The linker on AIX does not track inter-library dependencies, so do it ourselves
            combine_libtool_flags
            ;;
        hpux:native)
            DLO_LINK="-shared"
            LIB_LINK="-shared"

            if [ "$MODE" = "library" ]
            then
                COMBINED_LIBDEPS="$COMBINED_LIBDEPS c"
            fi
            combine_libtool_flags
            ;;
    esac

    [ -z "$CONFTEST" ] && COMBINED_LDFLAGS="$COMBINED_LDFLAGS $MK_RPATHFLAGS"

    for lib in ${COMBINED_LIBDEPS}
    do
        _LIBS="$_LIBS -l${lib}"
    done

    [ "${_object%/*}" != "${_object}" ] && mk_mkdir "${_object%/*}"

    case "$MODE" in
        library)
            mk_msg_domain "link"
            mk_msg "$pretty ($MK_CANONICAL_SYSTEM)"
            mk_run_or_fail ${CPROG} ${LIB_LINK} -o "$_object" "$@" ${COMBINED_LDFLAGS} -fPIC ${_LIBS}
            mk_run_link_posthooks "$_object"
            ;;
        dlo)
            mk_msg_domain "link"
            mk_msg "$pretty ($MK_CANONICAL_SYSTEM)"
            mk_run_or_fail ${CPROG} ${DLO_LINK} -o "$_object" "$@" ${COMBINED_LDFLAGS} -fPIC ${_LIBS}
            mk_run_link_posthooks "$_object"
            ;;
        program)
            mk_msg_domain "link"
            mk_msg "$pretty ($MK_CANONICAL_SYSTEM)"
            mk_run_or_fail ${CPROG} -o "$_object" "$@" ${COMBINED_LDFLAGS} ${_LIBS}
            mk_run_link_posthooks "$_object"
            ;;
        ar)
            mk_msg_domain "ar"
            mk_msg "$pretty ($MK_CANONICAL_SYSTEM)"
            mk_safe_rm "$_object"
            mk_run_or_fail ${MK_AR} -cru "$_object" "$@"
            mk_run_or_fail ${MK_RANLIB} "$_object"
            ;;
        la)
            mk_msg_domain "la"
            mk_msg "$pretty ($MK_CANONICAL_SYSTEM)"
            create_libtool_archive
            ;;
    esac
}

object="$1"
shift
mk_pretty_path "$object"
pretty="$result"

if [ -z "$CONFTEST" -a "$MK_SYSTEM" = "host" -a "$MK_MULTIARCH" = "combine" -a "$MODE" != "ar" -a "$MODE" != "la" ]
then
    for _isa in ${MK_HOST_ISAS}
    do
        mk_system "host/$_isa"
        mk_basename "$object"
        mk_tempfile "$_isa.$result"
        part="$result"
        do_link "$part" "$@"
        parts="$parts $part"
    done
    mk_system host
    _mk_compiler_multiarch_combine "$object" ${parts}
    mk_tempfile_clear
else
    do_link "$object" "$@"
fi