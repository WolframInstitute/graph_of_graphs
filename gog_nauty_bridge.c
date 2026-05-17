#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <nauty/nausparse.h>
#include <nauty/traces.h>

static void set_error(char *err, size_t err_len, const char *fmt, ...)
{
    if (err == NULL || err_len == 0) return;

    va_list ap;
    va_start(ap, fmt);
    vsnprintf(err, err_len, fmt, ap);
    va_end(ap);
    err[err_len - 1] = '\0';
}

static int checked_code_len(int n)
{
    if (n <= 0) return -1;
    if (n > 46340) return -1;
    return n * (n + 1) / 2;
}

static void free_sparsegraph_storage(sparsegraph *sg)
{
    if (sg == NULL) return;
    free(sg->v);
    free(sg->d);
    free(sg->e);
    sg->v = NULL;
    sg->d = NULL;
    sg->e = NULL;
    sg->w = NULL;
    sg->vlen = sg->dlen = sg->elen = sg->wlen = 0;
}

static int build_matrix_from_code(
    int n,
    const int *code,
    int code_len,
    int **matrix_out,
    char *err,
    size_t err_len)
{
    int expected = checked_code_len(n);
    if (expected < 0 || code_len != expected) {
        set_error(err, err_len, "bad code length %d for n=%d; expected %d", code_len, n, expected);
        return 1;
    }

    int *matrix = (int *)calloc((size_t)n * (size_t)n, sizeof(int));
    if (matrix == NULL) {
        set_error(err, err_len, "out of memory allocating %dx%d matrix", n, n);
        return 1;
    }

    int k = 0;
    for (int i = 0; i < n; ++i) {
        for (int j = i; j < n; ++j) {
            int value = code[k++];
            if (value < 0) {
                free(matrix);
                set_error(err, err_len, "negative edge multiplicity in code");
                return 1;
            }
            matrix[(size_t)i * (size_t)n + (size_t)j] = value;
            matrix[(size_t)j * (size_t)n + (size_t)i] = value;
        }
    }

    *matrix_out = matrix;
    return 0;
}

static int add_arc(sparsegraph *sg, size_t *cursor, int from, int to, char *err, size_t err_len)
{
    size_t pos = cursor[from]++;
    if (pos >= sg->nde) {
        set_error(err, err_len, "sparsegraph arc cursor overflow");
        return 1;
    }
    sg->e[pos] = to;
    return 0;
}

static int build_incidence_sparsegraph(
    int n,
    const int *matrix,
    sparsegraph *sg,
    int *nonloop_count_out,
    int *loop_count_out,
    char *err,
    size_t err_len)
{
    int nonloop_count = 0;
    int loop_count = 0;

    for (int i = 0; i < n; ++i) {
        loop_count += matrix[(size_t)i * (size_t)n + (size_t)i];
        for (int j = i + 1; j < n; ++j) {
            nonloop_count += matrix[(size_t)i * (size_t)n + (size_t)j];
        }
    }

    int total = n + nonloop_count + loop_count;
    size_t nde = (size_t)4 * (size_t)nonloop_count + (size_t)2 * (size_t)loop_count;

    SG_INIT(*sg);
    sg->nv = total;
    sg->nde = nde;
    sg->vlen = (size_t)total;
    sg->dlen = (size_t)total;
    sg->elen = nde;
    sg->wlen = 0;
    sg->w = NULL;
    sg->v = (size_t *)calloc((size_t)total, sizeof(size_t));
    sg->d = (int *)calloc((size_t)total, sizeof(int));
    sg->e = (int *)calloc(nde == 0 ? 1 : nde, sizeof(int));
    if (sg->v == NULL || sg->d == NULL || sg->e == NULL) {
        free_sparsegraph_storage(sg);
        set_error(err, err_len, "out of memory allocating sparsegraph");
        return 1;
    }

    int edge_node = n;
    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
            int multiplicity = matrix[(size_t)i * (size_t)n + (size_t)j];
            for (int r = 0; r < multiplicity; ++r) {
                sg->d[i] += 1;
                sg->d[j] += 1;
                sg->d[edge_node] += 2;
                edge_node += 1;
            }
        }
    }
    for (int i = 0; i < n; ++i) {
        int multiplicity = matrix[(size_t)i * (size_t)n + (size_t)i];
        for (int r = 0; r < multiplicity; ++r) {
            sg->d[i] += 1;
            sg->d[edge_node] += 1;
            edge_node += 1;
        }
    }

    size_t offset = 0;
    for (int v = 0; v < total; ++v) {
        sg->v[v] = offset;
        offset += (size_t)sg->d[v];
    }
    if (offset != nde) {
        free_sparsegraph_storage(sg);
        set_error(err, err_len, "internal sparsegraph degree mismatch");
        return 1;
    }

    size_t *cursor = (size_t *)malloc((size_t)total * sizeof(size_t));
    if (cursor == NULL) {
        free_sparsegraph_storage(sg);
        set_error(err, err_len, "out of memory allocating sparsegraph cursors");
        return 1;
    }
    memcpy(cursor, sg->v, (size_t)total * sizeof(size_t));

    edge_node = n;
    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
            int multiplicity = matrix[(size_t)i * (size_t)n + (size_t)j];
            for (int r = 0; r < multiplicity; ++r) {
                if (add_arc(sg, cursor, i, edge_node, err, err_len) ||
                    add_arc(sg, cursor, edge_node, i, err, err_len) ||
                    add_arc(sg, cursor, j, edge_node, err, err_len) ||
                    add_arc(sg, cursor, edge_node, j, err, err_len)) {
                    free(cursor);
                    free_sparsegraph_storage(sg);
                    return 1;
                }
                edge_node += 1;
            }
        }
    }
    for (int i = 0; i < n; ++i) {
        int multiplicity = matrix[(size_t)i * (size_t)n + (size_t)i];
        for (int r = 0; r < multiplicity; ++r) {
            if (add_arc(sg, cursor, i, edge_node, err, err_len) ||
                add_arc(sg, cursor, edge_node, i, err, err_len)) {
                free(cursor);
                free_sparsegraph_storage(sg);
                return 1;
            }
            edge_node += 1;
        }
    }

    free(cursor);
    sortlists_sg(sg);

    *nonloop_count_out = nonloop_count;
    *loop_count_out = loop_count;
    return 0;
}

static int build_partition(
    int n,
    int nonloop_count,
    int loop_count,
    int *lab,
    int *ptn)
{
    int total = n + nonloop_count + loop_count;
    int pos = 0;

    for (int v = 0; v < n; ++v) {
        lab[pos] = v;
        ptn[pos] = (v == n - 1) ? 0 : 1;
        pos += 1;
    }

    if (nonloop_count > 0) {
        for (int e = 0; e < nonloop_count; ++e) {
            lab[pos] = n + e;
            ptn[pos] = (e == nonloop_count - 1) ? 0 : 1;
            pos += 1;
        }
    }

    if (loop_count > 0) {
        int start = n + nonloop_count;
        for (int e = 0; e < loop_count; ++e) {
            lab[pos] = start + e;
            ptn[pos] = (e == loop_count - 1) ? 0 : 1;
            pos += 1;
        }
    }

    return pos == total ? 0 : 1;
}

int gog_nauty_bridge_version(void)
{
    return 1;
}

int gog_canonicalize_traces(
    int n,
    const int *code,
    int code_len,
    int *out_code,
    int *out_order,
    char *err,
    size_t err_len)
{
    if (code == NULL || out_code == NULL || out_order == NULL) {
        set_error(err, err_len, "null pointer passed to gog_canonicalize_traces");
        return 1;
    }

    int *matrix = NULL;
    if (build_matrix_from_code(n, code, code_len, &matrix, err, err_len)) {
        return 1;
    }

    sparsegraph sg;
    int nonloop_count = 0;
    int loop_count = 0;
    if (build_incidence_sparsegraph(n, matrix, &sg, &nonloop_count, &loop_count, err, err_len)) {
        free(matrix);
        return 1;
    }

    int total = sg.nv;
    int *lab = (int *)calloc((size_t)total, sizeof(int));
    int *ptn = (int *)calloc((size_t)total, sizeof(int));
    int *orbits = (int *)calloc((size_t)total, sizeof(int));
    if (lab == NULL || ptn == NULL || orbits == NULL) {
        free(lab);
        free(ptn);
        free(orbits);
        free_sparsegraph_storage(&sg);
        free(matrix);
        set_error(err, err_len, "out of memory allocating nauty work arrays");
        return 1;
    }

    if (build_partition(n, nonloop_count, loop_count, lab, ptn)) {
        free(lab);
        free(ptn);
        free(orbits);
        free_sparsegraph_storage(&sg);
        free(matrix);
        set_error(err, err_len, "failed to build nauty colour partition");
        return 1;
    }

    DEFAULTOPTIONS_TRACES(options);
    options.getcanon = TRUE;
    options.defaultptn = FALSE;
    options.verbosity = 0;
    options.outfile = NULL;

    TracesStats stats;
    memset(&stats, 0, sizeof(stats));
    SG_DECL(canong);

    Traces(&sg, lab, ptn, orbits, &options, &stats, &canong);
    if (stats.errstatus != 0) {
        set_error(err, err_len, "Traces failed with errstatus=%d", stats.errstatus);
        SG_FREE(canong);
        free(lab);
        free(ptn);
        free(orbits);
        free_sparsegraph_storage(&sg);
        free(matrix);
        return 1;
    }

    int *seen = (int *)calloc((size_t)n, sizeof(int));
    if (seen == NULL) {
        set_error(err, err_len, "out of memory validating canonical order");
        SG_FREE(canong);
        free(lab);
        free(ptn);
        free(orbits);
        free_sparsegraph_storage(&sg);
        free(matrix);
        return 1;
    }

    for (int i = 0; i < n; ++i) {
        int original = lab[i];
        if (original < 0 || original >= n || seen[original]) {
            free(seen);
            set_error(err, err_len, "Traces did not keep original vertices in the first colour cell");
            SG_FREE(canong);
            free(lab);
            free(ptn);
            free(orbits);
            free_sparsegraph_storage(&sg);
            free(matrix);
            return 1;
        }
        seen[original] = 1;
        out_order[i] = original;
    }
    free(seen);

    int k = 0;
    for (int a = 0; a < n; ++a) {
        int i = out_order[a];
        for (int b = a; b < n; ++b) {
            int j = out_order[b];
            out_code[k++] = matrix[(size_t)i * (size_t)n + (size_t)j];
        }
    }

    SG_FREE(canong);
    free(lab);
    free(ptn);
    free(orbits);
    free_sparsegraph_storage(&sg);
    free(matrix);
    if (err != NULL && err_len > 0) err[0] = '\0';
    return 0;
}
