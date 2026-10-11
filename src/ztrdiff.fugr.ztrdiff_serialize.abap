FUNCTION ztrdiff_serialize.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_ITEMS) TYPE  STRING
*"     VALUE(IV_LANGU) TYPE  LANGU DEFAULT 'E'
*"  EXPORTING
*"     VALUE(EV_ZIP) TYPE  XSTRING
*"     VALUE(EV_INFO) TYPE  STRING
*"----------------------------------------------------------------------
  " Serialize a list of TADIR objects with abapGit and return a ZIP (for
  " transport-request comparison across systems; deployed identically on
  " every compared system).
  "   IV_ITEMS: one object per line, format  PGMID|OBJECT|OBJ_NAME
  "   EV_ZIP  : abapGit files + _status.txt with per-object status lines
  "             OBJ_TYPE|OBJ_NAME|STATUS|DETAIL   (STATUS: OK / NOT_FOUND /
  "             UNSUPPORTED / SKIPPED / INVALID)
  "   EV_INFO : one-line summary incl. FM_VERSION for version-pin checks
  " Only R3TR entries are serialized; LIMU lines are reported as SKIPPED
  " (parent R3TR objects carry the same content).

  CONSTANTS: c_version TYPE string VALUE 'v1'.

  TYPES: BEGIN OF ty_status,
           obj_type TYPE tadir-object,
           obj_name TYPE tadir-obj_name,
           status   TYPE string,
           detail   TYPE string,
         END OF ty_status.

  DATA: lt_lines  TYPE STANDARD TABLE OF string WITH EMPTY KEY,
        lt_status TYPE STANDARD TABLE OF ty_status WITH EMPTY KEY,
        lt_seen   TYPE STANDARD TABLE OF string WITH EMPTY KEY,
        lo_zip    TYPE REF TO cl_abap_zip,
        ls_item   TYPE zif_abapgit_definitions=>ty_item,
        lv_ok     TYPE i,
        lv_skip   TYPE i.

  CREATE OBJECT lo_zip.

  SPLIT iv_items AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.

  LOOP AT lt_lines INTO DATA(lv_line) WHERE table_line IS NOT INITIAL.
    DATA(lv_norm) = lv_line.
    REPLACE ALL OCCURRENCES OF |\r| IN lv_norm WITH ||.
    CONDENSE lv_norm.

    SPLIT lv_norm AT '|' INTO DATA(lv_pgmid) DATA(lv_object) DATA(lv_obj_name).
    IF lv_obj_name IS INITIAL.
      APPEND VALUE #( obj_type = lv_object status = 'INVALID' detail = lv_norm )
        TO lt_status.
      CONTINUE.
    ENDIF.

    DATA(lv_key) = lv_pgmid && lv_object && lv_obj_name.
    READ TABLE lt_seen WITH KEY table_line = lv_key TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      CONTINUE.
    ENDIF.
    APPEND lv_key TO lt_seen.

    IF lv_pgmid <> 'R3TR'.
      APPEND VALUE #( obj_type = lv_object obj_name = lv_obj_name
                      status = 'SKIPPED' detail = 'LIMU: serialize parent R3TR' )
        TO lt_status.
      lv_skip = lv_skip + 1.
      CONTINUE.
    ENDIF.

    CLEAR ls_item.
    ls_item-obj_type = lv_object.
    ls_item-obj_name = lv_obj_name.
    SELECT SINGLE devclass, srcsystem, masterlang FROM tadir
      WHERE pgmid = 'R3TR' AND object = @lv_object AND obj_name = @lv_obj_name
      INTO ( @ls_item-devclass, @ls_item-srcsystem, @ls_item-origlang ).
    IF sy-subrc <> 0 OR ls_item-devclass IS INITIAL.
      APPEND VALUE #( obj_type = lv_object obj_name = lv_obj_name
                      status = 'NOT_FOUND' detail = 'no TADIR entry' )
        TO lt_status.
      CONTINUE.
    ENDIF.

    IF zcl_abapgit_objects=>is_supported( ls_item ) = abap_false.
      APPEND VALUE #( obj_type = lv_object obj_name = lv_obj_name
                      status = 'UNSUPPORTED' detail = |abapGit type { lv_object }| )
        TO lt_status.
      CONTINUE.
    ENDIF.

    IF zcl_abapgit_objects=>exists( ls_item ) = abap_false.
      APPEND VALUE #( obj_type = lv_object obj_name = lv_obj_name
                      status = 'NOT_FOUND' detail = 'no active object' )
        TO lt_status.
      CONTINUE.
    ENDIF.

    TRY.
        DATA(ls_ser) = zcl_abapgit_objects=>serialize(
          is_item        = ls_item
          io_i18n_params = zcl_abapgit_i18n_params=>new(
              iv_main_language = COND #( WHEN ls_item-origlang IS NOT INITIAL
                                         THEN ls_item-origlang
                                         ELSE iv_langu ) ) ).

        LOOP AT ls_ser-files INTO DATA(ls_file).
          DATA(lv_name) = ls_file-path && ls_file-filename.
          IF strlen( lv_name ) > 0 AND lv_name(1) = '/'.
            lv_name = lv_name+1.
          ENDIF.
          IF strlen( lv_name ) = 0.
            lv_name = lv_object && '_' && lv_obj_name.
          ENDIF.
          lo_zip->add( name = lv_name content = ls_file-data ).
        ENDLOOP.

        APPEND VALUE #( obj_type = lv_object obj_name = lv_obj_name
                        status = 'OK' detail = |{ lines( ls_ser-files ) } files| )
          TO lt_status.
        lv_ok = lv_ok + 1.

      CATCH cx_root INTO DATA(lx_root).
        APPEND VALUE #( obj_type = lv_object obj_name = lv_obj_name
                        status = 'ERROR' detail = lx_root->get_text( ) )
          TO lt_status.
    ENDTRY.
  ENDLOOP.

  DATA lt_txt TYPE STANDARD TABLE OF string WITH EMPTY KEY.
  APPEND |SYSID={ sy-sysid } CLIENT={ sy-mandt } FM_VERSION={ c_version }| TO lt_txt.
  APPEND |OBJECTS={ lines( lt_status ) } OK={ lv_ok } SKIPPED={ lv_skip }| TO lt_txt.
  LOOP AT lt_status INTO DATA(ls_st).
    APPEND ls_st-obj_type && '|' && ls_st-obj_name && '|' && ls_st-status && '|' && ls_st-detail
      TO lt_txt.
  ENDLOOP.

  lo_zip->add( name = '_status.txt'
               content = cl_abap_codepage=>convert_to(
                   concat_lines_of( table = lt_txt sep = cl_abap_char_utilities=>newline ) ) ).

  ev_zip  = lo_zip->save( ).
  ev_info = |SYSID={ sy-sysid };FM_VERSION={ c_version };ITEMS={ lines( lt_status ) };| &&
            |OK={ lv_ok };SKIPPED={ lv_skip }|.

ENDFUNCTION.
