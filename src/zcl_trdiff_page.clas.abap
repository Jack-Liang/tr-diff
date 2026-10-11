CLASS zcl_trdiff_page DEFINITION
  PUBLIC
  INHERITING FROM zcl_abapgit_gui_page_diff_base
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    TYPES ty_files TYPE zif_abapgit_git_definitions=>ty_files_tt .

    " Build a ready-to-show page wrapped like abapGit's own diff page
    CLASS-METHODS create
      IMPORTING
        !it_dev_files TYPE ty_files
        !it_tgt_files TYPE ty_files
        !iv_title     TYPE string DEFAULT 'Transport Diff'
      RETURNING
        VALUE(ri_page) TYPE REF TO zif_abapgit_gui_renderable
      RAISING
        zcx_abapgit_exception .

    " Build without the GUI wrapper (headless, for tests/batch)
    CLASS-METHODS build
      IMPORTING
        !it_dev_files TYPE ty_files
        !it_tgt_files TYPE ty_files
      RETURNING
        VALUE(ro_page) TYPE REF TO zcl_trdiff_page
      RAISING
        zcx_abapgit_exception .

    " Wrap a prebuilt page like abapGit's own diff page
    CLASS-METHODS wrap
      IMPORTING
        !io_page      TYPE REF TO zcl_trdiff_page
        !iv_title     TYPE string DEFAULT 'Transport Diff'
      RETURNING
        VALUE(ri_page) TYPE REF TO zif_abapgit_gui_renderable
      RAISING
        zcx_abapgit_exception .

    METHODS get_diff_count
      RETURNING
        VALUE(rv_count) TYPE i .

    METHODS get_diff_names
      RETURNING
        VALUE(rt_names) TYPE zif_abapgit_definitions=>ty_string_tt .

  PROTECTED SECTION.

    METHODS get_files_and_status REDEFINITION .

  PRIVATE SECTION.

    METHODS build_diffs
      IMPORTING
        !it_dev_files TYPE ty_files
        !it_tgt_files TYPE ty_files
      RAISING
        zcx_abapgit_exception .

    METHODS owner_of
      IMPORTING
        !iv_filename  TYPE string
      EXPORTING
        !ev_obj_type  TYPE tadir-object
        !ev_obj_name  TYPE tadir-obj_name .
ENDCLASS .



CLASS zcl_trdiff_page IMPLEMENTATION.


  METHOD create.

    ri_page = wrap( io_page  = build( it_dev_files = it_dev_files
                                      it_tgt_files = it_tgt_files )
                    iv_title = iv_title ).

  ENDMETHOD.


  METHOD wrap.

    ri_page = zcl_abapgit_gui_page_hoc=>create(
      iv_page_title         = iv_title
      iv_page_layout        = get_page_layout( )
      ii_page_menu_provider = io_page
      ii_child_component    = io_page ).

  ENDMETHOD.


  METHOD build.

    CREATE OBJECT ro_page.
    ro_page->build_diffs( it_dev_files = it_dev_files
                          it_tgt_files = it_tgt_files ).

  ENDMETHOD.


  METHOD get_diff_count.

    rv_count = lines( mt_diff_files ).

  ENDMETHOD.


  METHOD get_diff_names.

    LOOP AT mt_diff_files INTO DATA(ls_diff).
      APPEND |{ ls_diff-lstate }/{ ls_diff-rstate } { ls_diff-filename }| TO rt_names.
    ENDLOOP.

  ENDMETHOD.


  METHOD get_files_and_status.

    " The page is built from two ZIP snapshots, there is no repo to refresh.
    zcx_abapgit_exception=>raise( 'Cross-system diff is static - refresh is not supported' ).

  ENDMETHOD.


  METHOD build_diffs.

    DATA: lt_names  TYPE STANDARD TABLE OF string WITH EMPTY KEY,
          ls_status TYPE zif_abapgit_definitions=>ty_result,
          lv_found  TYPE abap_bool.

    mt_diff_files = VALUE #( ).

    LOOP AT it_dev_files INTO DATA(ls_file) WHERE filename <> '_status.txt'.
      APPEND ls_file-filename TO lt_names.
    ENDLOOP.

    LOOP AT it_tgt_files INTO ls_file WHERE filename <> '_status.txt'.
      READ TABLE lt_names WITH KEY table_line = ls_file-filename TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND ls_file-filename TO lt_names.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_names INTO DATA(lv_name).

      READ TABLE it_tgt_files WITH KEY filename = lv_name INTO DATA(ls_tgt).
      lv_found = boolc( sy-subrc = 0 ).
      READ TABLE it_dev_files WITH KEY filename = lv_name INTO DATA(ls_dev).
      IF sy-subrc = 0 AND lv_found = abap_true AND ls_dev-data = ls_tgt-data.
        CONTINUE. " identical files are not part of the review
      ENDIF.

      CLEAR ls_status.
      ls_status-filename = lv_name.
      owner_of( EXPORTING iv_filename = lv_name
                IMPORTING ev_obj_type  = ls_status-obj_type
                          ev_obj_name  = ls_status-obj_name ).

      IF lv_found = abap_false.
        ls_status-lstate = 'A'.                    " would be added in target
      ELSEIF sy-subrc <> 0.
        ls_status-rstate = 'A'.                    " exists only in target
      ELSE.
        ls_status-lstate = 'M'.                    " will be changed in target
        ls_status-rstate = 'M'.
      ENDIF.

      append_diff( it_remote = it_tgt_files
                   it_local  = VALUE #( ( file = ls_dev ) )
                   is_status = ls_status ).

    ENDLOOP.

  ENDMETHOD.


  METHOD owner_of.

    DATA lt_parts TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    SPLIT iv_filename AT '.' INTO TABLE lt_parts.
    IF lines( lt_parts ) >= 3.
      " abapGit AFF naming: objname.objtype[.member].suffix
      ev_obj_name = to_upper( lt_parts[ 1 ] ).
      ev_obj_type = to_upper( lt_parts[ 2 ] ).
    ELSE.
      ev_obj_type = 'FILE'.
      ev_obj_name = to_upper( iv_filename ).
    ENDIF.

  ENDMETHOD.


ENDCLASS.

