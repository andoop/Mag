part of '../home_page.dart';

Widget _ocSheetDragHandle(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: context.oc.muted.withOpacity(0.35),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    ),
  );
}
