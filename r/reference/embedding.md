# Opt-in embedding-based construct-redundancy screen.

This screen is parity-exempt because its results depend on a
user-supplied embedding function whose outputs are not deterministic
across model versions or SDKs. It is the assistive counterpart to the
deterministic lexical screen in `tf_redundancy_check`, and it is
excluded from the parity contract and CI. See API_SPEC.md section 23.
