import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_action_handler.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_col_border.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_drag_data.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_row.dart';
import 'package:appflowy_editor/src/editor/util/platform_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TableCol extends StatefulWidget {
  const TableCol({
    super.key,
    required this.tableNode,
    required this.editorState,
    required this.colIdx,
    required this.tableStyle,
    required this.rowDragNotifier,
    required this.rowActionNotifier,
    required this.cellFocusNotifier,
    required this.colResizeHoverNotifier,
    this.menuBuilder,
    this.scrollController,
  });

  final int colIdx;
  final EditorState editorState;
  final TableNode tableNode;

  final TableBlockComponentMenuBuilder? menuBuilder;

  final TableStyle tableStyle;
  final TableRowDragNotifier rowDragNotifier;
  final TableRowActionNotifier rowActionNotifier;
  final TableCellFocusNotifier cellFocusNotifier;
  final ValueNotifier<int?> colResizeHoverNotifier;
  final ScrollController? scrollController;

  @override
  State<TableCol> createState() => _TableColState();
}

class _TableColState extends State<TableCol> {
  bool _colActionVisiblity = false;
  double? _cachedColWidth;

  Map<String, void Function()> listeners = {};
  // Store node references for proper cleanup
  final Map<String, Node> _listenerNodes = {};

  final Set<int> _pendingRowHeightUpdates = {};

  // Track which rows have been initialized to avoid redundant listener setup
  // Track which rows have been initialized to avoid redundant listener setup
  final Set<String> _initializedCellNodes = {};

  OverlayEntry? _overlayEntry;
  final Map<int, LayerLink> _layerLinks = {};

  // LayerLinks for cell handles (key: rowIndex)
  final Map<int, LayerLink> _cellLayerLinks = {};

  // GlobalKeys for cells to calculate exact render size
  final Map<int, GlobalKey> _cellKeys = {};
  final ValueNotifier<double> _selectionHeightNotifier = ValueNotifier(0.0);

  // Track if the left part of the table is visible (for row handle visibility)
  final ValueNotifier<bool> _isLeftPartVisibleNotifier = ValueNotifier<bool>(true);

  // Track if the right part of the table (where cell handle is) is visible (for cell handle visibility)
  final ValueNotifier<bool> _isRightPartVisibleNotifier = ValueNotifier<bool>(true);

  double _getColWidth() {
    if (_cachedColWidth != null) {
      return _cachedColWidth!;
    }
    final width = widget.tableNode.getColWidth(widget.colIdx);
    _cachedColWidth = width;
    return width;
  }

  @override
  void didUpdateWidget(TableCol oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update scroll listener if controller changed
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScrollChanged);
      widget.scrollController?.addListener(_onScrollChanged);
      _updateLeftPartVisibility();
    }
    // Reset cache when table node or column index changes
    if (oldWidget.tableNode != widget.tableNode || oldWidget.colIdx != widget.colIdx) {
      _cachedColWidth = null;
      // Clean up listeners for old nodes
      _cleanupListeners();
      _initializedCellNodes.clear();
      // Rebuild overlay if needed
      if (widget.colIdx == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateOverlay();
        });
      }
      // Rebuild cell handles overlay for all columns
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateCellHandlesOverlay();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Listen to scroll changes to determine if left part is visible
    widget.scrollController?.addListener(_onScrollChanged);
    _updateLeftPartVisibility();
    _updateRightPartVisibility();
    if (widget.colIdx == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateOverlay();
      });
    }
    // Initialize cell handles overlay for all columns
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateCellHandlesOverlay();
    });
  }

  void _onScrollChanged() {
    _updateLeftPartVisibility();
    _updateRightPartVisibility();
  }

  void _updateLeftPartVisibility() {
    bool isVisible;
    if (widget.scrollController == null || !widget.scrollController!.hasClients) {
      isVisible = true;
    } else {
      // The handle is positioned at offset -10 from the first column
      // Since the table has left padding of 10, the handle is at the very left edge
      // We consider it visible if scroll offset is <= 0 (or within a small threshold)
      isVisible = widget.scrollController!.offset <= 0;
    }
    if (_isLeftPartVisibleNotifier.value != isVisible) {
      _isLeftPartVisibleNotifier.value = isVisible;
    }
  }

  void _updateRightPartVisibility() {
    bool isVisible;
    if (widget.scrollController == null || !widget.scrollController!.hasClients) {
      isVisible = true;
    } else {
      try {
        final scrollPosition = widget.scrollController!.position;
        final scrollOffset = scrollPosition.pixels;
        final viewportWidth = scrollPosition.viewportDimension;

        // Calculate the left position of this column
        // Sum up widths of all previous columns
        double columnLeft = 0.0;
        for (int i = 0; i < widget.colIdx; i++) {
          columnLeft += widget.tableNode.getColWidth(i);
        }

        // Add the left padding (10px) that's applied to the table
        columnLeft += 10.0;

        // Calculate the right edge of the column (where the handle is positioned)
        final columnWidth = _getColWidth();
        final columnRight = columnLeft + columnWidth;

        // The viewport starts at scrollOffset and extends viewportWidth pixels
        final viewportLeft = scrollOffset;
        final viewportRight = scrollOffset + viewportWidth;

        // Check if the column's right edge (where the handle is anchored) is visible in the viewport
        // The handle should be visible only if the column's right edge is within the viewport bounds
        // When scrolling left, columnRight moves relative to viewportRight
        // If columnRight > viewportRight, the column is scrolled out to the right → hide handle
        // If columnRight < viewportLeft, the column is scrolled out to the left → hide handle
        // Use strict comparison to ensure handle is hidden when column is clearly out of view
        isVisible = columnRight >= viewportLeft && columnRight <= viewportRight;
      } catch (e) {
        // If there's any error (e.g., position not ready), assume visible
        isVisible = true;
      }
    }
    if (_isRightPartVisibleNotifier.value != isVisible) {
      _isRightPartVisibleNotifier.value = isVisible;
    }
  }

  OverlayEntry? _cellHandlesOverlayEntry;

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScrollChanged);
    _isLeftPartVisibleNotifier.dispose();
    _isRightPartVisibleNotifier.dispose();
    _removeOverlay();
    _removeCellHandlesOverlay();
    _cleanupListeners();
    _selectionHeightNotifier.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _removeCellHandlesOverlay() {
    _cellHandlesOverlayEntry?.remove();
    _cellHandlesOverlayEntry = null;
  }

  void _updateOverlay() {
    if (widget.colIdx != 0) return;

    _removeOverlay();

    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // We might need to listen to something to rebuild the overlay?
          // Actually, the OverlayEntry builder is called when overlay rebuilds.
          // But we need it to rebuild when rowActionNotifier changes.
          // So we wrap the whole stack in ListenableBuilder.
          ListenableBuilder(
            listenable:
                Listenable.merge([widget.rowActionNotifier, widget.cellFocusNotifier, _isLeftPartVisibleNotifier]),
            builder: (context, _) {
              return Stack(
                children: List.generate(widget.tableNode.rowsLen, (index) {
                  // Ensure we have a link for this row
                  if (!_layerLinks.containsKey(index)) return const SizedBox.shrink();

                  final isHovered = widget.rowActionNotifier.hoveredRowIndex == index;
                  final isFocused = widget.cellFocusNotifier.isRowFocused(index);
                  final isMobile = PlatformExtension.isMobile;
                  final shouldShow = (isMobile ? isFocused : isHovered) && _isLeftPartVisibleNotifier.value;

                  // If not visible, we can save performance by not rendering the handler?
                  // But we need to keep it in tree if it has state. TableActionHandler has state.
                  // However, visibility handles that.

                  return Positioned(
                    width: 20, // Arbitrary width for the handle area
                    child: CompositedTransformFollower(
                      link: _layerLinks[index]!,
                      showWhenUnlinked: false,
                      offset: const Offset(-10, 5), // Shift to the left gutter
                      child: TableActionHandler(
                        visible: shouldShow,
                        node: widget.tableNode.node,
                        editorState: widget.editorState,
                        position: index,
                        alignment: Alignment.centerLeft, // Align vertical center of cell
                        height: widget.tableNode.getRowHeight(index), // Confine to row height
                        menuBuilder: widget.menuBuilder,
                        dir: TableDirection.row,
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  void _updateCellHandlesOverlay() {
    _removeCellHandlesOverlay();

    final overlay = Overlay.of(context);
    _cellHandlesOverlayEntry = OverlayEntry(
      builder: (context) => ListenableBuilder(
        listenable: Listenable.merge([
          widget.cellFocusNotifier,
          _isRightPartVisibleNotifier,
        ]),
        builder: (context, _) {
          final focusedRow = widget.cellFocusNotifier.focusedRowIndex;
          final focusedCol = widget.cellFocusNotifier.focusedColIndex;

          if (focusedRow == null || focusedCol == null) {
            return const SizedBox.shrink();
          }

          // Get selection boundaries
          final minRow = widget.cellFocusNotifier.minRow;
          final maxRow = widget.cellFocusNotifier.maxRow;
          final maxCol = widget.cellFocusNotifier.maxCol;

          if (minRow == null || maxRow == null || maxCol == null) {
            return const SizedBox.shrink();
          }

          // Only show handle if this column is the rightmost column of the selection
          if (widget.colIdx != maxCol) {
            return const SizedBox.shrink();
          }

          // Anchor the handle to the top-most row of the selection
          final targetRow = minRow;

          // Ensure we have a link for this cell
          if (!_cellLayerLinks.containsKey(targetRow)) {
            return const SizedBox.shrink();
          }

          // Trigger height calculation in post frame
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _calculateSelectionHeight(minRow, maxRow);
          });

          final colWidth = _getColWidth();

          return ValueListenableBuilder<double>(
            valueListenable: _selectionHeightNotifier,
            builder: (context, height, _) {
              if (height == 0) return const SizedBox.shrink();

              // Use the same pattern as row handle - check visibility and pass to TableActionHandler
              final shouldShow = _isRightPartVisibleNotifier.value;

              return Positioned(
                width: 20, // Match the row handle width
                child: CompositedTransformFollower(
                  link: _cellLayerLinks[targetRow]!,
                  showWhenUnlinked: false,
                  followerAnchor: Alignment.center,
                  // Position strictly on the right border, centered vertically relative to the entire selection
                  // Offset from the top-right corner of the minRow cell
                  offset: Offset(colWidth, height / 2),
                  child: TableActionHandler(
                    visible: shouldShow,
                    node: widget.tableNode.node,
                    editorState: widget.editorState,
                    position: maxRow, // Pass the bottom-most row as position context
                    alignment: Alignment.center, // Center alignment
                    height: null,
                    menuBuilder: widget.menuBuilder,
                    dir: TableDirection.cell,
                    cellFocusNotifier: widget.cellFocusNotifier,
                  ),
                ),
              );
            },
          );
        },
      ),
    );

    overlay.insert(_cellHandlesOverlayEntry!);
  }

  void _cleanupListeners() {
    for (final entry in listeners.entries) {
      // Remove listener from stored node reference
      try {
        final node = _listenerNodes[entry.key];
        if (node != null) {
          node.removeListener(entry.value);
        }
      } catch (e) {
        // Node might have been disposed, ignore
      }
    }
    listeners.clear();
    _listenerNodes.clear();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> children = [];
    if (widget.colIdx == 0) {
      children.add(
        Padding(
          padding: EdgeInsets.only(top: 10),
          child: TableColBorder(
            resizable: false,
            tableNode: widget.tableNode,
            editorState: widget.editorState,
            colIdx: widget.colIdx,
            borderColor: widget.tableStyle.borderColor,
            borderHoverColor: widget.tableStyle.borderHoverColor,
          ),
        ),
      );
    }

    children.addAll([
      DragTarget<TableDragData>(
        onWillAcceptWithDetails: (details) {
          return details.data.dir == TableDirection.col &&
              details.data.node == widget.tableNode.node &&
              details.data.position != widget.colIdx;
        },
        onAcceptWithDetails: (details) {
          TableActions.move(
            widget.tableNode.node,
            details.data.position,
            widget.colIdx,
            widget.editorState,
            TableDirection.col,
          );
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          final draggedPosition = candidateData.isNotEmpty ? candidateData.first!.position : -1;
          final isMovingLeft = draggedPosition > widget.colIdx;

          return Stack(
            children: [
              SizedBox(
                width: _getColWidth(),
                child: Stack(
                  children: [
                    MouseRegion(
                      onEnter: (_) => setState(() => _colActionVisiblity = true),
                      onExit: (_) => setState(() => _colActionVisiblity = false),
                      child: Column(children: _buildCells(context)),
                    ),
                    ListenableBuilder(
                      listenable: widget.cellFocusNotifier,
                      builder: (context, child) {
                        final isFocused = widget.cellFocusNotifier.isColFocused(widget.colIdx);
                        // On mobile, show when cell is focused (selected)
                        // On desktop, show only on hover
                        final isMobile = PlatformExtension.isMobile;
                        final shouldShow = isMobile ? isFocused : _colActionVisiblity;
                        return Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 20, // Constrain to prevent blocking clicks on cells below
                          child: TableActionHandler(
                            visible: shouldShow,
                            node: widget.tableNode.node,
                            editorState: widget.editorState,
                            position: widget.colIdx,
                            alignment: Alignment.topCenter,
                            menuBuilder: widget.menuBuilder,
                            dir: TableDirection.col,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (isHovering)
                Positioned(
                  left: isMovingLeft ? -2 : null,
                  right: isMovingLeft ? null : -2,
                  top: 10,
                  bottom: 0,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: widget.tableStyle.borderHoverColor,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: widget.tableStyle.borderHoverColor.withValues(alpha: 0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      Padding(
        padding: EdgeInsets.only(top: 10),
        child: ValueListenableBuilder<int?>(
          valueListenable: widget.colResizeHoverNotifier,
          builder: (context, hoveredColIdx, _) {
            final isHovered = hoveredColIdx == widget.colIdx;
            return Container(
              width: widget.tableNode.config.borderWidth,
              color: isHovered ? widget.tableStyle.borderHoverColor : widget.tableStyle.borderColor,
            );
          },
        ),
      ),
    ]);

    // Use a Stack to allow the resize handle to be larger than the visible border
    // without affecting the layout of adjacent columns
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IntrinsicHeight(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        // Left Helper Handle: Resizes the PREVIOUS column (if not the first column)
        // This extends the hitbox of the previous column's right border into this column.
        if (widget.colIdx > 0)
          Positioned(
            left: 0,
            top: 10,
            bottom: 0,
            width: Platform.isMacOS || Platform.isAndroid ? 12 : 5.0, // Extends 12px into this column
            child: TableColBorder(
              resizable: true,
              tableNode: widget.tableNode,
              editorState: widget.editorState,
              // Bind to the previous column index
              colIdx: widget.colIdx - 1,
              // Helper is transparent, purely for hit testing
              borderColor: Colors.transparent,
              borderHoverColor: Colors.transparent,
              hitboxWidth: Platform.isMacOS || Platform.isAndroid ? 12 : 5.0,
              hitboxAlignment: Alignment.centerLeft,
              activeColNotifier: widget.colResizeHoverNotifier,
            ),
          ),
        // Right Handle: Resizes THIS column
        // This is the main handle that also draws the visible border.
        Positioned(
          right: 0,
          top: 10,
          bottom: 0,
          width: Platform.isMacOS || Platform.isAndroid ? 12 : 5.0, // Extends 12px into this column
          child: TableColBorder(
            resizable: true,
            tableNode: widget.tableNode,
            editorState: widget.editorState,
            colIdx: widget.colIdx,
            borderColor: Colors.transparent,
            borderHoverColor: Colors.transparent,
            hitboxWidth: Platform.isMacOS || Platform.isAndroid ? 12 : 5.0,
            hitboxAlignment: Alignment.centerRight,
            activeColNotifier: widget.colResizeHoverNotifier,
          ),
        ),
      ],
    );
  }

  void _calculateSelectionHeight(int minRow, int maxRow) {
    if (!mounted) return;

    final minKey = _cellKeys[minRow];
    final maxKey = _cellKeys[maxRow];

    if (minKey?.currentContext == null || maxKey?.currentContext == null) return;

    final minRenderBox = minKey!.currentContext!.findRenderObject() as RenderBox;
    final maxRenderBox = maxKey!.currentContext!.findRenderObject() as RenderBox;

    // Calculate height difference relative to the minRenderBox
    // We want the vector from minBox top-left to maxBox bottom-left (vertical component)
    final topOfMin = minRenderBox.localToGlobal(Offset.zero);
    final bottomOfMax = maxRenderBox.localToGlobal(Offset(0, maxRenderBox.size.height));

    final heightCallback = bottomOfMax.dy - topOfMin.dy;

    // Add the borders in between?
    // localToGlobal should theoretically account for layout positions.
    // If there are gaps (borders) between cells on screen, the global positions reflect that.

    if (_selectionHeightNotifier.value != heightCallback) {
      _selectionHeightNotifier.value = heightCallback;
    }
  }

  List<Widget> _buildCells(BuildContext context) {
    final rowsLen = widget.tableNode.rowsLen;
    final List<Widget> cells = [];
    final Widget cellBorder = Container(
      height: widget.tableNode.config.borderWidth,
      color: widget.tableStyle.borderColor,
    );

    for (var i = 0; i < rowsLen; i++) {
      final node = widget.tableNode.getCell(widget.colIdx, i);

      // Only set up listeners once per cell node
      final cellKey = '${node.id}_$i';
      if (!_initializedCellNodes.contains(cellKey)) {
        addListener(node, i);
        // Only add listener to first child if it exists
        if (node.children.isNotEmpty) {
          addListener(node.children.first, i);
        }
        _initializedCellNodes.add(cellKey);
      }

      // Ensure key exists
      _cellKeys.putIfAbsent(i, () => GlobalKey());

      Widget cellWidget = KeyedSubtree(
        key: _cellKeys[i],
        child: RepaintBoundary(
          key: ValueKey('cell_${node.id}_${widget.colIdx}_$i'),
          child: widget.editorState.renderer.build(
            context,
            node,
          ),
        ),
      );

      // Wrap the cell with the providers
      cellWidget = MultiProvider(
        providers: [
          ChangeNotifierProvider<TableRowActionNotifier>.value(
            value: widget.rowActionNotifier,
          ),
          ChangeNotifierProvider<TableCellFocusNotifier>.value(
            value: widget.cellFocusNotifier,
          ),
        ],
        child: cellWidget,
      );

      // Wrap the cell with the row action notifier for hover detection
      // Wrap ALL cells with TableRowDragTarget so any cell can accept the drop
      cellWidget = TableRowDragTarget(
        tableNode: widget.tableNode.node,
        rowIdx: i,
        colIdx: widget.colIdx,
        editorState: widget.editorState,
        dragNotifier: widget.rowDragNotifier,
        cellFocusNotifier: widget.cellFocusNotifier,
        child: cellWidget,
      );

      // Add CompositedTransformTarget for the first column to anchor row handles
      if (widget.colIdx == 0) {
        _layerLinks.putIfAbsent(i, () => LayerLink());
        cellWidget = CompositedTransformTarget(
          link: _layerLinks[i]!,
          child: cellWidget,
        );
      }

      // Add CompositedTransformTarget for all cells to anchor cell handles on right border
      _cellLayerLinks.putIfAbsent(i, () => LayerLink());
      cellWidget = CompositedTransformTarget(
        link: _cellLayerLinks[i]!,
        child: cellWidget,
      );

      // Add visual indicator line when row is hovered
      cellWidget = ListenableBuilder(
        listenable: widget.rowDragNotifier,
        builder: (context, child) {
          final isRowHovered = widget.rowDragNotifier.hoveredRow == i;

          // Get the dragged row position to determine direction
          final draggedRowPosition = widget.rowDragNotifier.draggedRowPosition;
          final isMovingUp = draggedRowPosition != null && draggedRowPosition > i;

          return Stack(
            children: [
              child!,
              if (isRowHovered)
                Positioned(
                  left: 0,
                  right: 0,
                  top: isMovingUp ? -2 : null,
                  bottom: isMovingUp ? null : -2,
                  child: IgnorePointer(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: widget.tableStyle.borderHoverColor,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: widget.tableStyle.borderHoverColor.withValues(alpha: 0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        child: cellWidget,
      );

      // Add visual indicator line when cell is focused
      cellWidget = ListenableBuilder(
        listenable: widget.cellFocusNotifier,
        builder: (context, child) {
          final isCellFocused = widget.cellFocusNotifier.isCellFocused(i, widget.colIdx);

          if (!isCellFocused) return child!;

          final minRow = widget.cellFocusNotifier.minRow;
          final maxRow = widget.cellFocusNotifier.maxRow;
          final minCol = widget.cellFocusNotifier.minCol;
          final maxCol = widget.cellFocusNotifier.maxCol;

          // Determine borders based on position in selection range
          final isTop = i == minRow;
          final isBottom = i == maxRow;
          final isLeft = widget.colIdx == minCol;
          final isRight = widget.colIdx == maxCol;

          final borderSide = BorderSide(
            color: widget.tableStyle.borderHoverColor,
            width: 1.5,
          );

          return Stack(
            children: [
              child!,
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: isTop ? borderSide : BorderSide.none,
                        bottom: isBottom ? borderSide : BorderSide.none,
                        left: isLeft ? borderSide : BorderSide.none,
                        right: isRight ? borderSide : BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: cellWidget,
      );

      cells.addAll([
        cellWidget,
        cellBorder,
      ]);
    }

    return [
      Padding(
        padding: EdgeInsets.only(top: 10),
        child: Column(
          children: [
            cellBorder,
            ...cells,
          ],
        ),
      ),
    ];
  }

  void addListener(Node node, int row) {
    if (listeners.containsKey(node.id)) {
      return;
    }

    listeners[node.id] = () {
      int? currentRow = node.attributes[TableCellBlockKeys.rowPosition] as int?;
      if (currentRow == null && node.parent != null) {
        currentRow = node.parent!.attributes[TableCellBlockKeys.rowPosition] as int?;
      }
      if (currentRow != null) {
        updateRowHeightCallback(currentRow);
      }
    };
    _listenerNodes[node.id] = node;
    node.addListener(listeners[node.id]!);
  }

  void updateRowHeightCallback(int row) {
    // Add to pending updates
    _pendingRowHeightUpdates.add(row);

    if (!mounted || _pendingRowHeightUpdates.isEmpty) {
      return;
    }

    // Process all pending row height updates in a single transaction
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final rowsToUpdate = Set<int>.from(_pendingRowHeightUpdates);
      _pendingRowHeightUpdates.clear();

      // Filter out invalid rows
      final validRows = rowsToUpdate.where((r) => r < widget.tableNode.rowsLen).toSet();
      if (validRows.isEmpty) {
        return;
      }

      // Reset cached width when row height changes as it might affect column layout
      _cachedColWidth = null;

      // Batch update all affected rows in a single transaction
      final transaction = widget.editorState.transaction;
      for (final row in validRows) {
        widget.tableNode.updateRowHeight(
          row,
          editorState: widget.editorState,
          transaction: transaction,
        );
      }

      if (transaction.operations.isNotEmpty) {
        transaction.afterSelection = transaction.beforeSelection;
        widget.editorState.apply(transaction);
      }
    });
  }
}
