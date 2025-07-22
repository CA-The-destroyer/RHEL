# Add User to Wheel Group

A simple Ansible playbook to add a specified user to the `wheel` group on RHEL systems, granting sudo privileges.

## Requirements

- Ansible 2.9+
- RHEL 7/8/9 or compatible distribution
- SSH access to target hosts with sufficient privileges

## Playbook

**File:** `add-to-wheel.yml`

```yaml
---
- name: Add parameterized user to wheel group
  hosts: your_rhel_hosts
  become: true

  vars:
    sudo_user: notarealuser  # default, override with -e sudo_user=<username>

  tasks:
    - name: Ensure {{ sudo_user }} is a member of wheel
      user:
        name: "{{ sudo_user }}"
        groups: wheel
        append: yes

    - name: Enable wheel group in sudoers (optional)
      lineinfile:
        path: /etc/sudoers
        regexp: '^# %wheel'
        line: '%wheel ALL=(ALL) ALL'
        validate: 'visudo -cf %s'
```

## Usage

```bash
# Default user 'notarealuser'
ansible-playbook add-to-wheel.yml

# Override user
ansible-playbook add-to-wheel.yml -e sudo_user=jdoe
```

## Variables

| Variable   | Default      | Description                            |
| ---------- | ------------ | -------------------------------------- |
| sudo\_user | notarealuser | The username to add to the wheel group |

## License

MIT

