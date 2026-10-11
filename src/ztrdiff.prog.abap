REPORT ztrdiff LINE-SIZE 200.

* Compare the objects of a transport request (dev system) against the
* current state of another system (e.g. production), shown in abapGit's
* own diff page. Requires FM ZTRDIFF_SERIALIZE (group ZTRDIFF) deployed
* identically on both systems - it serializes each object with abapGit.
*
* Usage:
*   TRKORR  = request in this system (tasks are included automatically)
*   OBJS    = direct object list, e.g. 'FUGR ZTRDIFF, CLAS ZCL_FOO'
*   DEST    = RFC destination of the target system (SM59); 'NONE' = here
* Run with F8 - the diff opens in abapGit's viewer (unified/split,
* filters and beacons included). Refresh is not supported (static diff).

TABLES: sscrfields.

SELECTION-SCREEN BEGIN OF SCREEN 1001.
" dummy screen hosting the abapGit html viewer
SELECTION-SCREEN END OF SCREEN 1001.

PARAMETERS:
  p_trkorr TYPE e070-trkorr,
  p_objs   TYPE c LENGTH 255,
  p_dest   TYPE rfcdes-rfcdest DEFAULT 'NONE' OBLIGATORY,
  p_langu  TYPE sy-langu DEFAULT 'E'.

DATA: go_page TYPE REF TO zif_abapgit_gui_renderable,
      go_gui  TYPE REF TO zcl_abapgit_gui.

*---------------------------------------------------------------------*
* Minimal router: answers every navigation with the prebuilt diff page
*---------------------------------------------------------------------*
CLASS lcl_router DEFINITION FINAL.

  PUBLIC SECTION.
    INTERFACES zif_abapgit_gui_event_handler.

ENDCLASS.

CLASS lcl_router IMPLEMENTATION.

  METHOD zif_abapgit_gui_event_handler~on_event.

    rs_handled-page  = go_page.
    rs_handled-state = zcl_abapgit_gui=>c_event_state-new_page.

  ENDMETHOD.

ENDCLASS.

*---------------------------------------------------------------------*
START-OF-SELECTION.

  TRY.
      PERFORM run.
    CATCH zcx_abapgit_exception INTO DATA(lx_ag) ##NEEDED.
      MESSAGE lx_ag->get_text( ) TYPE 'E'.
  ENDTRY.

AT SELECTION-SCREEN OUTPUT.
  IF sy-dynnr = 1001 AND go_gui IS BOUND.
    PERFORM output.
  ENDIF.

AT SELECTION-SCREEN ON EXIT-COMMAND.
  IF sy-dynnr = 1001.
    PERFORM exit_gui.
  ENDIF.

*---------------------------------------------------------------------*
FORM run RAISING zcx_abapgit_exception.

  DATA: lv_items   TYPE string,
        lv_zip_dev TYPE xstring,
        lv_zip_tgt TYPE xstring,
        lv_info    TYPE string,
        lt_dev     TYPE zcl_trdiff_page=>ty_files,
        lt_tgt     TYPE zcl_trdiff_page=>ty_files.

  PERFORM build_item_list CHANGING lv_items.

  CALL FUNCTION 'ZTRDIFF_SERIALIZE'
    EXPORTING
      iv_items = lv_items
      iv_langu = p_langu
    IMPORTING
      ev_zip   = lv_zip_dev
      ev_info  = lv_info.
  WRITE: / 'dev    ' && lv_info.

  CALL FUNCTION 'ZTRDIFF_SERIALIZE'
    DESTINATION p_dest
    EXPORTING
      iv_items = lv_items
      iv_langu = p_langu
    IMPORTING
      ev_zip   = lv_zip_tgt
      ev_info  = lv_info
    EXCEPTIONS
      communication_failure = 1
      system_failure        = 2
      OTHERS                = 3.
  IF sy-subrc <> 0.
    MESSAGE ID sy-msgid TYPE 'E' NUMBER sy-msgno
            WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
  ENDIF.
  WRITE: / 'target ' && lv_info.

  PERFORM unzip USING lv_zip_dev CHANGING lt_dev.
  PERFORM unzip USING lv_zip_tgt CHANGING lt_tgt.

  DATA(lo_page) = zcl_trdiff_page=>build( it_dev_files = lt_dev
                                          it_tgt_files = lt_tgt ).
  DATA(lv_count) = lo_page->get_diff_count( ).
  WRITE: / |files with differences: { lv_count }|.

  IF lv_count = 0.
    MESSAGE 'No differences - target already matches dev' TYPE 'S'.
    RETURN.
  ENDIF.

  DATA(lv_title) = COND #( WHEN p_trkorr IS NOT INITIAL
                           THEN |Diff { p_trkorr }: { sy-sysid } vs { p_dest }|
                           ELSE |Diff objects vs { p_dest }| ).

  go_page = zcl_trdiff_page=>wrap( io_page = lo_page
                                   iv_title = lv_title ).

  CREATE OBJECT go_gui
    EXPORTING
      io_component = NEW lcl_router( ).

  go_gui->go_home( 'ztrdiff_start' ).
  CALL SELECTION-SCREEN 1001.

ENDFORM.

FORM build_item_list CHANGING cv_items TYPE string
                      RAISING zcx_abapgit_exception.

  DATA: lv_items TYPE string,
        lt_tasks TYPE STANDARD TABLE OF e070-trkorr WITH EMPTY KEY.

  IF p_trkorr IS NOT INITIAL.

    SELECT trkorr FROM e070
      WHERE trkorr = @p_trkorr OR strkorr = @p_trkorr
      INTO TABLE @lt_tasks.
    IF sy-subrc <> 0.
      zcx_abapgit_exception=>raise( |Request { p_trkorr } not found in E070| ).
    ENDIF.

    SELECT pgmid AS a1, object AS a2, obj_name AS a3
      FROM e071
      FOR ALL ENTRIES IN @lt_tasks
      WHERE trkorr = @lt_tasks-table_line
      INTO TABLE @DATA(lt_e071).
    IF sy-subrc <> 0 OR lt_e071 IS INITIAL.
      zcx_abapgit_exception=>raise( |Request { p_trkorr } has no objects| ).
    ENDIF.

    LOOP AT lt_e071 INTO DATA(ls_e071).
      lv_items = lv_items && ls_e071-a1 && '|' && ls_e071-a2 && '|' &&
                 ls_e071-a3 && cl_abap_char_utilities=>newline.
    ENDLOOP.

  ELSEIF p_objs IS NOT INITIAL.

    SPLIT p_objs AT ',' INTO TABLE DATA(lt_chunks).
    LOOP AT lt_chunks INTO DATA(lv_chunk).
      CONDENSE lv_chunk.
      SPLIT lv_chunk AT space INTO TABLE DATA(lt_parts).
      CASE lines( lt_parts ).
        WHEN 2.
          lv_items = lv_items && 'R3TR' && '|' && to_upper( lt_parts[ 1 ] ) && '|' &&
                     to_upper( lt_parts[ 2 ] ) && cl_abap_char_utilities=>newline.
        WHEN 3.
          lv_items = lv_items && to_upper( lt_parts[ 1 ] ) && '|' && to_upper( lt_parts[ 2 ] ) && '|' &&
                     to_upper( lt_parts[ 3 ] ) && cl_abap_char_utilities=>newline.
        WHEN OTHERS.
          IF lv_chunk IS NOT INITIAL.
            zcx_abapgit_exception=>raise( |Bad object entry: { lv_chunk }| ).
          ENDIF.
      ENDCASE.
    ENDLOOP.
    IF lv_items IS INITIAL.
      zcx_abapgit_exception=>raise( 'Enter a TRKORR or an object list' ).
    ENDIF.

  ELSE.

    zcx_abapgit_exception=>raise( 'Enter a TRKORR or an object list' ).

  ENDIF.

  cv_items = lv_items.

ENDFORM.

FORM unzip USING    iv_zip TYPE xstring
           CHANGING ct_files TYPE zcl_trdiff_page=>ty_files.

  DATA: lo_zip     TYPE REF TO cl_abap_zip,
        lv_content TYPE xstring.

  CREATE OBJECT lo_zip.
  CALL METHOD lo_zip->load
    EXPORTING
      zip             = iv_zip
    EXCEPTIONS
      zip_parse_error = 1
      OTHERS          = 2.
  IF sy-subrc <> 0.
    MESSAGE 'Cannot parse serialization ZIP' TYPE 'E'.
  ENDIF.

  LOOP AT lo_zip->files INTO DATA(ls_file).
    CALL METHOD lo_zip->get
      EXPORTING
        name                   = ls_file-name
      IMPORTING
        content                = lv_content
      EXCEPTIONS
        zip_index_error        = 1
        zip_decompression_error = 2
        OTHERS                 = 3.
    IF sy-subrc = 0.
      APPEND VALUE #( path = '' filename = ls_file-name data = lv_content ) TO ct_files.
    ENDIF.
  ENDLOOP.

ENDFORM.

FORM output.

  DATA: lt_ucomm TYPE TABLE OF sy-ucomm.

  PERFORM set_pf_status IN PROGRAM rsdbrunt IF FOUND.

  APPEND 'CRET' TO lt_ucomm.
  APPEND 'SPOS' TO lt_ucomm.

  CALL FUNCTION 'RS_SET_SELSCREEN_STATUS'
    EXPORTING
      p_status  = sy-pfkey
    TABLES
    p_exclude = lt_ucomm.

  TRY.
      go_gui->set_focus( ).
    CATCH zcx_abapgit_exception INTO DATA(lx) ##NEEDED.
      MESSAGE lx->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.

ENDFORM.

FORM exit_gui.

  TRY.
      CASE sscrfields-ucomm.
        WHEN 'CBAC' OR 'CCAN'.
          IF go_gui->back( iv_graceful = abap_true ) = abap_true.
            go_gui->free( ).
            CLEAR: go_gui, go_page.
          ELSE.
            LEAVE TO SCREEN 1001.
          ENDIF.
      ENDCASE.
    CATCH zcx_abapgit_exception INTO DATA(lx) ##NEEDED.
      MESSAGE lx->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.

ENDFORM.
